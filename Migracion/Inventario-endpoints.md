# Inventario de endpoints — API Daytona (.NET Framework 4.5)

Generado el 13/10/2026 leyendo los 35 controllers de la rama main (commit 3788d54). Es la lista de contrato que la API nueva en .NET 10 tiene que respetar: misma ruta, mismo verbo, mismos roles y misma forma de respuesta.

Total: 184 endpoints en 34 controllers (sin contar HomeController, que es MVC). La web los llama desde 42 páginas; la app mobile usa 7.

## Hallazgos

1. Siete archivos no están en UTF-8 sino en Latin-1: DetallePedidoController, EstadoPedidoController, MarcaController, ModeloController, PedidoController, RubroController y Models/JwtHelper.cs. Hoy compila bien porque Visual Studio en Windows los lee con la página de códigos del sistema, pero .NET 10 asume UTF-8 y "Dueño" pasaría a ser "Due?o": los 12 endpoints de esos controllers que nombran al Dueño lo rechazarían con 403 (listar marcas, modelos, rubros, pedidos y estados). Hay que convertirlos a UTF-8 al pasarlos, o mejor todavía, sacar los nombres de rol del código (punto de permisos del plan).

2. ValuesController es el ejemplo que trae la plantilla de Visual Studio: 5 endpoints sin autenticación que no hacen nada. No se migra.

3. Nueve endpoints no los llama nadie (ni la web ni la app). No se migran salvo que se decida lo contrario:
   - GET api/Analisis/MapaCalor
   - GET api/Busqueda/Cobertura
   - GET api/Busqueda/Oportunidades
   - POST api/Compras/Pedido/{id:int}/Recibir
   - DELETE api/DetallePedido/{id}
   - DELETE api/Pedido/{id}
   - GET api/ProveedorRepuesto/Sugerencias
   - GET api/Repuesto/PrecioSugerido
   - PUT api/Repuesto/{id:int}/AplicarPrecio
   Los DELETE de Pedido y DetallePedido quedaron de antes: hoy un pedido se cancela con PUT y no se borra. El de Recibir es el circuito viejo de recepción en un paso; hoy la recepción va por Iniciar y Confirmar. MapaCalor llega dentro de Analisis/Periodo.

4. Dos endpoints anónimos, a propósito: POST api/Usuario/Login y POST api/SolicitudReset. Todo lo demás pide JWT.

5. Hay 20 combinaciones distintas de roles escritas a mano en los atributos (por ejemplo "Dueño,Administrador,Supervisor" y "Administrador,Supervisor,Vendedor"). Es la misma deuda que en el front: conviene pasarlas a permisos con nombre ("ventas.cargar", "compras.recibir") y que cada rol tenga su lista en la base.

6. La app mobile arma la dirección de la API con la IP de Metro y, en un build de producción, cae a localhost:52954. Para la Etapa 1 hay que reemplazarlo por EXPO_PUBLIC_API_URL y agregar .env al .gitignore de daytona-mobile (hoy no está).

7. La app mobile usa: Usuario/Login, SolicitudReset, Cliente, Configuracion/Venta, Venta (GET y POST), Venta/{id}/Detalle y Busqueda. Son los primeros que hay que probar contra la API nueva porque un cambio ahí rompe la app sin que se note en la web.

## Endpoints por controller

Formato: VERBO ruta — roles — páginas que lo usan. La columna de páginas sale de buscar la ruta en el código del front, así que puede marcar de más una página que solo nombra la ruta; para lo que dice SIN USO se revisó a mano. "JWT" es cualquier usuario logueado.

### Analisis (4)

- GET api/Analisis/Pronostico — Dueño,Administrador,Analista — Dashboard
- GET api/Analisis/PuntoEquilibrio — Dueño,Administrador,Analista — ReporteVentas
- GET api/Analisis/MapaCalor — Dueño,Administrador,Supervisor,Analista — SIN USO
- GET api/Analisis/Periodo — Dueño,Administrador,Supervisor,Analista — Dashboard

### Busqueda (3)

- GET api/Busqueda — Dueño,Administrador,Supervisor,Vendedor,Analista — Buscador, mobile:app/venta/index.tsx
- GET api/Busqueda/Oportunidades — Dueño,Administrador,Supervisor,Analista — SIN USO
- GET api/Busqueda/Cobertura — Dueño,Administrador,Analista — SIN USO

### Cliente (6)

- GET api/Cliente — Dueño,Administrador,Supervisor,Vendedor — CargarVenta, ClienteForm, ClientesListado, mobile:app/venta/confirmar.tsx
- GET api/Cliente/{id} — Dueño,Administrador,Supervisor,Vendedor — CargarVenta, ClienteForm, ClientesListado, mobile:app/venta/confirmar.tsx
- POST api/Cliente — Administrador,Supervisor,Vendedor — CargarVenta, mobile:app/venta/confirmar.tsx
- PUT api/Cliente/{id} — Administrador,Supervisor,Vendedor — CargarVenta, ClientesListado
- DELETE api/Cliente/{id} — Administrador,Supervisor,Vendedor — ClientesListado
- PUT api/Cliente/{id:int}/Activar — Administrador,Supervisor,Vendedor — ClientesListado

### Compras (23)

- GET api/Compras/Pedido/{id:int}/Recepcion — Dueño,Administrador,Supervisor,Vendedor,Analista — RecepcionPedido
- POST api/Compras/StockMinimo — Dueño,Administrador,Supervisor — StockRepuestos
- GET api/Compras/Reposicion — Dueño,Administrador,Supervisor,Vendedor — PedidoNuevo
- GET api/Compras/ResumenRecepcion — Dueño,Administrador,Supervisor,Analista — ListadoPedido
- POST api/Compras/Pedido/{id:int}/Recibir — Dueño,Administrador,Supervisor — SIN USO
- POST api/Compras/Pedido/{id:int}/Iniciar — Dueño,Administrador,Supervisor,Vendedor — RecepcionPedido
- POST api/Compras/Recepcion/{id:int}/Confirmar — Dueño,Administrador,Supervisor,Vendedor — RecepcionPedido
- GET api/Compras/Incidencias — Dueño,Administrador,Supervisor,Analista — CuentaProveedores
- POST api/Compras/Recepcion/{id:int}/Anular — Dueño,Administrador — CuentaProveedores, RecepcionPedido
- POST api/Compras/Pedido/{id:int}/CerrarFaltantes — Dueño,Administrador,Supervisor — RecepcionPedido
- POST api/Compras/Pedido/{id:int}/LeerFactura — Dueño,Administrador,Supervisor,Vendedor — RecepcionPedido
- GET api/Compras/Facturas — Dueño,Administrador,Supervisor,Analista — CuentaProveedores
- POST api/Compras/CuentasProveedor/{id:int}/SaldoInicial — Dueño,Administrador — CuentaProveedores
- POST api/Compras/Recepcion/{id:int}/Adjunto — Dueño,Administrador,Supervisor — CuentaProveedores, RecepcionPedido
- POST api/Compras/Proveedor/{id:int}/DiasPago — Dueño,Administrador — CuentaProveedores
- POST api/Compras/Incidencias/Reclamar — Dueño,Administrador,Supervisor,Vendedor — CuentaProveedores
- POST api/Compras/NotasCredito — Dueño,Administrador — CuentaProveedores
- POST api/Compras/Incidencias/{id:int}/Resolver — Dueño,Administrador,Supervisor — CuentaProveedores
- GET api/Compras/CuentasProveedor — Dueño,Administrador,Supervisor,Analista — CuentaProveedores
- GET api/Compras/CuentasProveedor/{id:int} — Dueño,Administrador,Supervisor,Analista — CuentaProveedores
- POST api/Compras/CuentasProveedor/{id:int}/Ajuste — Dueño,Administrador — CuentaProveedores
- POST api/Compras/Pagos — Dueño,Administrador — CuentaProveedores, RecepcionPedido
- POST api/Compras/Pagos/{id:int}/Anular — Dueño,Administrador — CuentaProveedores, RecepcionPedido

### Configuracion (5)

- GET api/Configuracion/Parametros — Dueño,Administrador — Configuracion
- PUT api/Configuracion/Parametro — Dueño,Administrador — Configuracion
- GET api/Configuracion/Venta — Dueño,Administrador,Supervisor,Vendedor — CargarVenta, layout.js, mobile:app/venta/carrito.tsx
- GET api/Configuracion/Margenes — Dueño,Administrador — Configuracion
- PUT api/Configuracion/Margen — Dueño,Administrador — Configuracion

### CuentaCorriente (5)

- GET api/CuentaCorriente — Dueño,Administrador,Supervisor,Vendedor — CargarVenta, CuentaCorriente, layout.js
- GET api/CuentaCorriente/{id} — Dueño,Administrador,Supervisor,Vendedor — CargarVenta, CuentaCorriente, layout.js
- GET api/CuentaCorriente/{id:int}/Movimientos — Dueño,Administrador,Supervisor,Vendedor — CuentaCorriente, layout.js
- POST api/CuentaCorriente/{id:int}/Pago — Dueño,Administrador,Supervisor,Vendedor — CargarVenta, CuentaCorriente
- POST api/CuentaCorriente/{id:int}/Ajuste — Dueño,Administrador — CuentaCorriente, layout.js

### DetallePedido (3)

- GET api/DetallePedido — Dueño,Administrador,Supervisor,Vendedor — PedidoNuevo
- POST api/DetallePedido — Administrador,Supervisor,Vendedor — PedidoNuevo
- DELETE api/DetallePedido/{id} — Administrador,Supervisor,Vendedor — SIN USO

### DetallePresupuesto (1)

- POST api/DetallePresupuesto — Administrador,Supervisor,Vendedor — CargarVenta

### EstadoPedido (6)

- GET api/EstadoPedido — Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema — EstadoPedidoForm, EstadosPedidoListado
- GET api/EstadoPedido/{id} — Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema — EstadoPedidoForm, EstadosPedidoListado
- POST api/EstadoPedido — Administrador — EstadoPedidoForm
- PUT api/EstadoPedido/{id} — Administrador — EstadosPedidoListado
- DELETE api/EstadoPedido/{id} — Administrador — EstadosPedidoListado
- PUT api/EstadoPedido/{id:int}/Activar — Administrador — EstadosPedidoListado

### EstadoVenta (6)

- GET api/EstadoVenta — Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema — EstadosVentaListado, EstadoVentaForm
- GET api/EstadoVenta/{id} — Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema — EstadosVentaListado, EstadoVentaForm
- POST api/EstadoVenta — Administrador — EstadoVentaForm
- PUT api/EstadoVenta/{id} — Administrador — EstadosVentaListado
- DELETE api/EstadoVenta/{id} — Administrador — EstadosVentaListado
- PUT api/EstadoVenta/{id:int}/Activar — Administrador — EstadosVentaListado

### Finanzas (13)

- GET api/Finanzas/Cuentas — Dueño,Administrador,Analista — CuentaProveedores, Gastos, MovimientosEspeciales, RecepcionPedido
- POST api/Finanzas/Adjunto — Dueño,Administrador,Supervisor — CuentaProveedores, Gastos, RecepcionPedido
- GET api/Finanzas/Adjunto/{id:int} — Dueño,Administrador,Supervisor,Analista — CuentaProveedores, Gastos, RecepcionPedido
- GET api/Finanzas/TiposGasto — Dueño,Administrador,Analista — Gastos
- GET api/Finanzas/Gastos — Dueño,Administrador,Analista — Gastos
- GET api/Finanzas/Gastos/Resumen — Dueño,Administrador,Analista — Gastos
- POST api/Finanzas/Gastos — Dueño,Administrador — Gastos
- POST api/Finanzas/Gastos/{id:int}/Pagar — Dueño,Administrador — Gastos
- POST api/Finanzas/Gastos/{id:int}/AnularPago — Dueño,Administrador — Gastos
- POST api/Finanzas/Gastos/{id:int}/Anular — Dueño,Administrador — Gastos
- GET api/Finanzas/MovimientosEspeciales — Dueño,Administrador,Analista — MovimientosEspeciales
- POST api/Finanzas/MovimientosEspeciales — Dueño,Administrador — MovimientosEspeciales
- POST api/Finanzas/MovimientosEspeciales/{id:int}/Anular — Dueño — MovimientosEspeciales

### Indicador (1)

- GET api/Indicador — Dueño,Administrador,Supervisor,Vendedor,Analista — layout.js

### Login (1)

- POST api/Usuario/Login — anónimo — Login, mobile:app/index.tsx

### Marca (6)

- GET api/Marca — Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema — CargarRepuesto, CargarVenta, MarcaForm, MarcasListado, ModeloForm, ModelosListado, PedidoNuevo, ReporteStockCritico, mobile:app/index.tsx, mobile:app/recuperar.tsx, mobile:components/Marca.tsx
- GET api/Marca/{id} — Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema — CargarRepuesto, CargarVenta, MarcaForm, MarcasListado, ModeloForm, ModelosListado, PedidoNuevo, ReporteStockCritico, mobile:app/index.tsx, mobile:app/recuperar.tsx, mobile:components/Marca.tsx
- POST api/Marca — Administrador,Analista — CargarVenta, PedidoNuevo, mobile:app/index.tsx, mobile:app/recuperar.tsx
- PUT api/Marca/{id} — Administrador,Analista — CargarVenta, MarcasListado, ModelosListado
- DELETE api/Marca/{id} — Administrador,Analista — MarcasListado, ModelosListado
- PUT api/Marca/{id:int}/Activar — Administrador,Analista — MarcasListado, ModelosListado

### MedioPago (4)

- GET api/MedioPago — Dueño,Administrador,Supervisor,Vendedor,Analista — Caja, CargarVenta
- GET api/MedioPago/Venta/{idVenta:int} — Dueño,Administrador,Supervisor,Vendedor,Analista — CargarVenta
- GET api/MedioPago/Cuentas — Dueño,Administrador,Analista — Caja
- GET api/MedioPago/Resumen — Dueño,Administrador,Supervisor,Analista — Caja

### Modelo (7)

- GET api/Modelo — Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema — CargarRepuesto, CargarVenta, ModeloForm, ModelosListado
- GET api/Modelo/{id} — Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema — CargarRepuesto, CargarVenta, ModeloForm, ModelosListado
- GET api/Modelo/Uno/{id:int} — Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema — ModeloForm
- POST api/Modelo — Administrador,Analista — CargarVenta
- PUT api/Modelo/{id} — Administrador,Analista — CargarVenta, ModelosListado
- DELETE api/Modelo/{id} — Administrador,Analista — ModelosListado
- PUT api/Modelo/{id:int}/Activar — Administrador,Analista — ModelosListado

### MovimientoCaja (3)

- GET api/MovimientoCaja — Administrador,Vendedor,Dueño — Caja
- GET api/MovimientoCaja/Saldo — Administrador,Vendedor,Dueño — Caja
- POST api/MovimientoCaja — Administrador,Vendedor — Caja

### MovimientoStock (3)

- GET api/MovimientoStock — Administrador,Analista,Dueño,Vendedor — AjusteStock
- GET api/MovimientoStock/{id} — Administrador,Analista,Dueño,Vendedor — AjusteStock
- POST api/MovimientoStock — Administrador,Analista,Vendedor — AjusteStock

### NotasCliente (5)

- GET api/NotasCliente/Venta/{id:int} — Dueño,Administrador,Supervisor — DevolucionVenta
- GET api/NotasCliente/Cuentas — Dueño,Administrador,Supervisor — DevolucionVenta
- POST api/NotasCliente/Credito — Dueño,Administrador,Supervisor — DevolucionVenta
- POST api/NotasCliente/Debito — Dueño,Administrador — CuentaCorriente
- GET api/NotasCliente — Dueño,Administrador,Supervisor,Analista — CuentaCorriente, DevolucionVenta

### Notificacion (1)

- GET api/Notificacion/Resumen — Dueño,Administrador — layout.js

### Pedido (5)

- GET api/Pedido — Dueño,Administrador,Supervisor,Vendedor — Index, layout.js, ListadoPedido, PedidoNuevo, RecepcionPedido
- GET api/Pedido/{id} — Dueño,Administrador,Supervisor,Vendedor — Index, layout.js, ListadoPedido, PedidoNuevo, RecepcionPedido
- POST api/Pedido — Administrador,Supervisor,Vendedor,Sistema — PedidoNuevo, RecepcionPedido
- PUT api/Pedido/{id} — Administrador,Supervisor,Vendedor — ListadoPedido
- DELETE api/Pedido/{id} — Administrador — SIN USO

### Presupuesto (5)

- GET api/Presupuesto — Dueño,Administrador,Supervisor,Vendedor — CargarVenta, ListadoPresupuestos, ProveedorForm
- GET api/Presupuesto/{id} — Dueño,Administrador,Supervisor,Vendedor — CargarVenta, ListadoPresupuestos, ProveedorForm
- POST api/Presupuesto — Administrador,Supervisor,Vendedor — CargarVenta
- PUT api/Presupuesto/{id} — Administrador,Supervisor,Vendedor,Sistema — CargarVenta
- DELETE api/Presupuesto/{id} — Dueño,Administrador,Supervisor — ListadoPresupuestos

### Proveedor (6)

- GET api/Proveedor — Dueño,Administrador,Supervisor,Vendedor — Buscador, CatalogoProveedores, CuentaProveedores, Gastos, ListadoPedido, PedidoNuevo, ProveedoresListado, ProveedorForm
- GET api/Proveedor/{id} — Dueño,Administrador,Supervisor,Vendedor — Buscador, CatalogoProveedores, CuentaProveedores, Gastos, ListadoPedido, PedidoNuevo, ProveedoresListado, ProveedorForm
- POST api/Proveedor — Administrador — CatalogoProveedores, CuentaProveedores, Gastos, PedidoNuevo
- PUT api/Proveedor/{id} — Administrador — Buscador, CatalogoProveedores, ListadoPedido, ProveedoresListado
- DELETE api/Proveedor/{id} — Administrador — ProveedoresListado
- PUT api/Proveedor/{id:int}/Activar — Administrador — ProveedoresListado

### ProveedorRepuesto (4)

- GET api/ProveedorRepuesto — Dueño,Administrador,Supervisor,Vendedor,Analista — Buscador, CatalogoProveedores
- GET api/ProveedorRepuesto/Buscar — Administrador,Supervisor,Analista — Buscador, CatalogoProveedores
- GET api/ProveedorRepuesto/Sugerencias — Administrador,Analista — SIN USO
- PUT api/ProveedorRepuesto/{id:int}/Enlazar — Administrador,Analista — Buscador, CatalogoProveedores

### Reporte (6)

- GET api/Reporte/StockCritico — Dueño,Administrador,Supervisor,Vendedor,Analista — ReporteStockCritico
- GET api/Reporte/VentasResumen — Dueño,Administrador,Supervisor — ReporteVentas
- GET api/Reporte/VentasPorDia — Dueño,Administrador,Supervisor — ReporteVentas
- GET api/Reporte/CajaResumen — Dueño,Administrador — ReporteCaja
- GET api/Reporte/CajaPorConcepto — Dueño,Administrador — ReporteCaja
- GET api/Reporte/Dashboard — Dueño,Administrador,Supervisor — Dashboard

### Repuesto (11)

- GET api/Repuesto — Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema — AjusteStock, CargarRepuesto, CargarVenta, CatalogoProveedores, Index, ListadoPedido, PedidoNuevo, StockRepuestos
- GET api/Repuesto/{id} — Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema — AjusteStock, CargarRepuesto, CargarVenta, CatalogoProveedores, Index, ListadoPedido, PedidoNuevo, StockRepuestos
- POST api/Repuesto — Administrador,Analista — AjusteStock, CargarVenta, CatalogoProveedores, PedidoNuevo, StockRepuestos
- PUT api/Repuesto/{id} — Administrador,Analista — CargarVenta, CatalogoProveedores, ListadoPedido, StockRepuestos
- DELETE api/Repuesto/{id} — Administrador,Analista — StockRepuestos
- GET api/Repuesto/Filtrar — Administrador,Supervisor,Vendedor,Analista,Sistema — CargarVenta, PedidoNuevo
- GET api/Repuesto/PrecioSugerido — Dueño,Administrador,Analista — SIN USO
- PUT api/Repuesto/{id:int}/AplicarPrecio — Dueño,Administrador,Analista — SIN USO
- POST api/Repuesto/IncorporarDesdeLista — Administrador,Analista — CatalogoProveedores
- GET api/Repuesto/{id:int}/OtrosProveedores — Dueño,Administrador,Supervisor,Analista — CatalogoProveedores
- PUT api/Repuesto/{id:int}/Activar — Administrador,Analista — StockRepuestos

### Rol (6)

- GET api/Rol — Administrador — RolesListado, RolForm, UsuarioForm
- GET api/Rol/{id} — Administrador — RolesListado, RolForm, UsuarioForm
- POST api/Rol — Administrador — RolForm
- PUT api/Rol/{id} — Administrador — RolesListado
- DELETE api/Rol/{id} — Administrador — RolesListado
- PUT api/Rol/{id:int}/Activar — Administrador — RolesListado

### Rubro (6)

- GET api/Rubro — Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema — CargarRepuesto, CargarVenta, CatalogoProveedores, PedidoNuevo, ReporteStockCritico, RubroForm, RubrosListado, StockRepuestos
- GET api/Rubro/{id} — Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema — CargarRepuesto, CargarVenta, CatalogoProveedores, PedidoNuevo, ReporteStockCritico, RubroForm, RubrosListado, StockRepuestos
- POST api/Rubro — Administrador,Analista — CargarVenta, CatalogoProveedores, PedidoNuevo, StockRepuestos
- PUT api/Rubro/{id} — Administrador,Analista — CargarVenta, CatalogoProveedores, RubrosListado, StockRepuestos
- DELETE api/Rubro/{id} — Administrador,Analista — RubrosListado, StockRepuestos
- PUT api/Rubro/{id:int}/Activar — Administrador,Analista — RubrosListado, StockRepuestos

### SesionCaja (5)

- GET api/SesionCaja/Actual — Dueño,Administrador,Supervisor,Vendedor,Analista — Caja
- POST api/SesionCaja/Abrir — Dueño,Administrador,Supervisor,Vendedor — Caja
- POST api/SesionCaja/Cerrar — Dueño,Administrador,Supervisor,Vendedor — Caja
- GET api/SesionCaja/Historial — Dueño,Administrador,Supervisor,Analista — Caja
- GET api/SesionCaja/Diferencias — Dueño,Administrador,Analista — Caja

### SolicitudReset (4)

- POST api/SolicitudReset — anónimo — Login, mobile:app/recuperar.tsx
- GET api/SolicitudReset/Pendientes — Administrador — UsuariosListado
- GET api/SolicitudReset — Administrador — Login, UsuariosListado, mobile:app/recuperar.tsx
- PUT api/SolicitudReset/{id:int}/Procesar — Administrador — UsuariosListado

### Stock (2)

- GET api/Stock — Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema — AjusteStock, CargarVenta, layout.js, PedidoNuevo, ReporteStockCritico
- GET api/Stock/{id} — Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema — AjusteStock, CargarVenta, layout.js, PedidoNuevo, ReporteStockCritico

### Usuario (7)

- GET api/Usuario — Administrador — CuentaCorriente, Login, UsuarioForm, UsuariosListado, mobile:app/index.tsx
- GET api/Usuario/{id} — Administrador — CuentaCorriente, Login, UsuarioForm, UsuariosListado, mobile:app/index.tsx
- POST api/Usuario — Administrador — CuentaCorriente, Login, mobile:app/index.tsx
- PUT api/Usuario/{id} — Administrador — UsuariosListado
- DELETE api/Usuario/{id} — Administrador — UsuariosListado
- PUT api/Usuario/{id:int}/Activar — Administrador — UsuariosListado
- PUT api/Usuario/{id:int}/ResetClave — Administrador — UsuariosListado

### Venta (6)

- GET api/Venta — Dueño,Administrador,Supervisor,Vendedor — CargarVenta, DevolucionVenta, Index, layout.js, ListadoVentas, mobile:app/_layout.tsx, mobile:app/venta/carrito.tsx, mobile:app/venta/confirmar.tsx, mobile:app/venta/index.tsx, mobile:app/ventas/index.tsx, mobile:app/ventas/[id].tsx
- GET api/Venta/{id} — Dueño,Administrador,Supervisor,Vendedor — CargarVenta, DevolucionVenta, Index, layout.js, ListadoVentas, mobile:app/_layout.tsx, mobile:app/venta/carrito.tsx, mobile:app/venta/confirmar.tsx, mobile:app/venta/index.tsx, mobile:app/ventas/index.tsx, mobile:app/ventas/[id].tsx
- GET api/Venta/{id:int}/Detalle — Dueño,Administrador,Supervisor,Vendedor — ListadoVentas, mobile:app/_layout.tsx, mobile:app/ventas/[id].tsx
- GET api/Venta/AnuladasRecientes — Dueño,Administrador,Supervisor — ListadoVentas
- POST api/Venta — Administrador,Supervisor,Vendedor — CargarVenta, DevolucionVenta, mobile:app/venta/confirmar.tsx
- PUT api/Venta/{id:int}/Anular — Administrador,Supervisor,Vendedor — ListadoVentas
