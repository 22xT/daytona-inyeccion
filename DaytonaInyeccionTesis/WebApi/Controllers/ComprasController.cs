using System;
using System.Collections.Generic;
using System.Globalization;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using System.Data;
using System.Data.SqlClient;
using System.Security.Claims;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class ComprasController : ApiController
    {
        public class MotivoDto { public string Motivo { get; set; } }
        public class AjusteDto { public decimal Monto { get; set; } public string Motivo { get; set; } }
        public class LeerFacturaDto { public int IdAdjunto { get; set; } }

        /* ================= RECEPCION ================= */

        // GET api/Compras/Pedido/5/Recepcion — cabecera, renglones con pendiente, recepciones anteriores
        [HttpGet, Route("api/Compras/Pedido/{id:int}/Recepcion")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista")]
        public IHttpActionResult ParaRecepcion(int id)
        {
            DataSet ds = new Compras().ParaRecepcion(id);
            if (ds.Tables.Count < 3 || ds.Tables[0].Rows.Count == 0) return NotFound();
            return Ok(new
            {
                Pedido = ds.Tables[0], Renglones = ds.Tables[1], Recepciones = ds.Tables[2],
                // Renglones de la recepcion en control, si hay una
                EnControl = ds.Tables.Count > 3 ? ds.Tables[3] : new DataTable()
            });
        }

        public class StockMinimoDto { public int IdRepuesto { get; set; } public int StockMinimo { get; set; } }

        [HttpPost, Route("api/Compras/StockMinimo")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult StockMinimo([FromBody] StockMinimoDto d)
        {
            if (d == null || d.IdRepuesto <= 0) return BadRequest("Falta el repuesto.");
            try { new Compras().SetStockMinimo(d.IdRepuesto, d.StockMinimo); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo guardar el mínimo.")); }
        }

        // GET api/Compras/Reposicion — que reponer, cuanto, y a quien se le puede comprar
        [HttpGet, Route("api/Compras/Reposicion")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Reposicion()
        {
            DataSet ds = new Compras().ReposicionSugerida();
            return Ok(new
            {
                Items = ds.Tables[0],
                Alternativas = ds.Tables[1],
                CubiertosEnCamino = ds.Tables.Count > 2 && ds.Tables[2].Rows.Count > 0 ? ds.Tables[2].Rows[0]["CubiertosEnCamino"] : 0,
                // Script 69: en que pedido esta lo que ya se pidio y cuando llega
                EnCamino = ds.Tables.Count > 3 ? ds.Tables[3] : new DataTable()
            });
        }

        public class GenerarPedidosDto { public List<PedidoLoteLinea> Lineas { get; set; } }
        public class PedirDto { public int IdProveedor { get; set; } public int IdRepuesto { get; set; } public int Cantidad { get; set; } }

        // POST api/Compras/Pedir — desde el buscador: suma al pedido en armado del proveedor
        [HttpPost, Route("api/Compras/Pedir")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Pedir([FromBody] PedirDto d)
        {
            if (d == null || d.IdProveedor <= 0 || d.IdRepuesto <= 0) return BadRequest("Faltan el proveedor o el repuesto.");
            try
            {
                DataTable t = new Compras().Pedir(d.IdProveedor, d.IdRepuesto, d.Cantidad);
                DataRow r = t.Rows[0];
                return Ok(new { IdPedido = r["IdPedido"], Proveedor = r["Proveedor"], Total = r["Total"], Renglones = r["Renglones"] });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo sumar al pedido.")); }
        }

        // POST api/Compras/Pedido/5/Enviar — ya se cargo en la web del proveedor
        [HttpPost, Route("api/Compras/Pedido/{id:int}/Enviar")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Enviar(int id)
        {
            try
            {
                DataRow r = new Compras().EnviarPedido(id).Rows[0];
                return Ok(new { FechaEnvio = r["FechaEnvio"], LlegadaEstimada = r["LlegadaEstimada"] });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo marcar como enviado.")); }
        }

        /* ---------- Carrito de compras ---------- */
        public class CarritoDto { public int IdRepuesto { get; set; } public int Cantidad { get; set; } public int? IdProveedor { get; set; } public string Origen { get; set; } }

        // GET api/Compras/Carrito — renglones y opciones de compra de cada uno
        [HttpGet, Route("api/Compras/Carrito")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Carrito()
        {
            DataSet ds = new Compras().CarritoGet();
            return Ok(new { Items = ds.Tables[0], Opciones = ds.Tables.Count > 1 ? ds.Tables[1] : new DataTable() });
        }

        // GET api/Compras/EnCamino — repuestos ya pedidos y sin recibir (script 91)
        [HttpGet, Route("api/Compras/EnCamino")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista")]
        public IHttpActionResult EnCamino()
        {
            try { return Ok(new Compras().EnCamino()); }
            catch (SqlException) { return Ok(new DataTable()); }   // sin el script 91 no avisa, pero no rompe
        }

        // POST api/Compras/Carrito — sumar (si ya estaba, suma la cantidad)
        [HttpPost, Route("api/Compras/Carrito")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult CarritoAgregar([FromBody] CarritoDto d)
        {
            if (d == null || d.IdRepuesto <= 0) return BadRequest("Falta el repuesto.");
            try
            {
                DataRow r = new Compras().CarritoAgregar(d.IdRepuesto, d.Cantidad, d.IdProveedor, d.Origen).Rows[0];
                return Ok(new { Renglones = r["Renglones"], Unidades = r["Unidades"] });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo sumar al carrito.")); }
        }

        // PUT api/Compras/Carrito/5 — cambiar cantidad o proveedor (0 = sacarlo)
        [HttpPut, Route("api/Compras/Carrito/{idRepuesto:int}")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult CarritoCambiar(int idRepuesto, [FromBody] CarritoDto d)
        {
            if (d == null) return BadRequest("Faltan los datos.");
            try { new Compras().CarritoCambiar(idRepuesto, d.Cantidad, d.IdProveedor); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo cambiar.")); }
        }

        // POST api/Compras/Carrito/Confirmar — todo a los pedidos en armado
        [HttpPost, Route("api/Compras/Carrito/Confirmar")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult CarritoConfirmar()
        {
            try { return Ok(new Compras().CarritoConfirmar()); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo confirmar el carrito.")); }
        }

        // DELETE api/Compras/Pedido/Renglon/5 — sacar un renglon de un pedido en armado
        [HttpDelete, Route("api/Compras/Pedido/Renglon/{id:int}")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult QuitarRenglon(int id)
        {
            try
            {
                DataRow r = new Compras().QuitarRenglon(id).Rows[0];
                return Ok(new { IdPedido = r["IdPedido"], RenglonesQuedan = r["RenglonesQuedan"] });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo sacar del pedido.")); }
        }

        // GET api/Compras/Pedido/5/ListaWeb — codigos y cantidades para cargar en la web
        [HttpGet, Route("api/Compras/Pedido/{id:int}/ListaWeb")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataTable ListaWeb(int id)
        {
            return new Compras().ListaWeb(id);
        }

        // GET api/Compras/Repuesto/5/Opciones — a quien se le puede comprar
        [HttpGet, Route("api/Compras/Repuesto/{id:int}/Opciones")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataTable Opciones(int id)
        {
            return new Compras().OpcionesCompra(id);
        }

        // POST api/Compras/Pedidos/Generar — reposicion: un pedido por proveedor, todo o nada
        [HttpPost, Route("api/Compras/Pedidos/Generar")]
        [AuthorizeJwt(Roles = "Administrador,Supervisor,Vendedor")]
        public IHttpActionResult GenerarPedidos([FromBody] GenerarPedidosDto d)
        {
            if (d == null || d.Lineas == null || d.Lineas.Count == 0) return BadRequest("No hay nada para pedir.");
            try { return Ok(new Compras().GenerarPedidos(d.Lineas)); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudieron generar los pedidos. No se creó ninguno.")); }
        }

        // GET api/Compras/ResumenRecepcion — para marcar los parciales en el listado
        [HttpGet, Route("api/Compras/ResumenRecepcion")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public DataTable ResumenRecepcion()
        {
            return new Compras().ResumenRecepcion();
        }

        [HttpPost, Route("api/Compras/Pedido/{id:int}/Recibir")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult Recibir(int id, [FromBody] Recepcion r)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (r == null || r.Lineas == null || r.Lineas.Count == 0) return BadRequest("Indicá qué llegó.");
            if (r.TotalComprobante <= 0) return BadRequest("Indicá el total del comprobante del proveedor.");

            try
            {
                Compras c = new Compras();
                DataTable dt = c.Recibir(id, r, idUsuario);
                int idRecepcion = Convert.ToInt32(dt.Rows[0]["IdRecepcion"]);

                // Si los datos salieron de leer la foto, la lectura queda asociada:
                // permite comparar despues lo que leyo el modelo con lo que se confirmo
                if (r.IdLecturaFactura.HasValue)
                {
                    try { c.VincularLectura(r.IdLecturaFactura.Value, idRecepcion); } catch (SqlException) { /* no frena la recepcion */ }
                }

                return Ok(new { IdRecepcion = idRecepcion, IdEstadoPedido = dt.Rows[0]["IdEstadoPedido"] });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo registrar la recepción.")); }
        }


        public class ControlDto { public List<RecepcionControlLinea> Lineas { get; set; } }

        // Paso 1: capturar la factura. Queda en control, sin stock ni deuda.
        [HttpPost, Route("api/Compras/Pedido/{id:int}/Iniciar")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Iniciar(int id, [FromBody] RecepcionInicio r)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (r == null || r.Lineas == null || r.Lineas.Count == 0) return BadRequest("Cargá los renglones de la factura.");
            try { return Ok(new { IdRecepcion = new Compras().IniciarRecepcion(id, r, idUsuario) }); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo guardar la factura.")); }
        }

        // Paso 3: confirmar lo controlado. Sube stock, registra deuda y abre incidencias.
        [HttpPost, Route("api/Compras/Recepcion/{id:int}/Confirmar")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Confirmar(int id, [FromBody] ControlDto d)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (d == null || d.Lineas == null || d.Lineas.Count == 0) return BadRequest("Faltan los renglones controlados.");
            try
            {
                DataTable dt = new Compras().ConfirmarRecepcion(id, d.Lineas, idUsuario);
                DataRow row = dt.Rows[0];
                return Ok(new { IdRecepcion = row["IdRecepcion"], IdEstadoPedido = row["IdEstadoPedido"],
                                Incidencias = row["Incidencias"], ImporteAReclamar = row["ImporteAReclamar"] });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo confirmar la recepción.")); }
        }

        [HttpGet, Route("api/Compras/Incidencias")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public DataTable Incidencias(int? idProveedor = null)
        {
            return new Compras().IncidenciasAbiertas(idProveedor);
        }

        [HttpPost, Route("api/Compras/Recepcion/{id:int}/Anular")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult AnularRecepcion(int id, [FromBody] MotivoDto m)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { new Compras().AnularRecepcion(id, m == null ? null : m.Motivo, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo anular la recepción.")); }
        }

        [HttpPost, Route("api/Compras/Pedido/{id:int}/CerrarFaltantes")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult CerrarFaltantes(int id, [FromBody] MotivoDto m)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { new Compras().CerrarFaltantes(id, m == null ? null : m.Motivo, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudieron cerrar los faltantes.")); }
        }


        /* ================= LECTURA DE FACTURA ================= */

        /* POST api/Compras/Pedido/5/LeerFactura  { IdAdjunto }
           Manda la foto ya subida a Claude, cruza los renglones con el
           catalogo y el pedido, y devuelve una PROPUESTA. No toca stock,
           costo ni deuda: eso pasa recien al confirmar con Recibir. */
        [HttpPost, Route("api/Compras/Pedido/{id:int}/LeerFactura")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public async Task<IHttpActionResult> LeerFactura(int id, [FromBody] LeerFacturaDto d)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (!LectorFactura.Configurado)
                return BadRequest("La lectura automática no está configurada en el servidor. Cargá la factura a mano: la recepción funciona igual.");
            if (d == null || d.IdAdjunto <= 0) return BadRequest("Primero adjuntá la foto o el PDF de la factura.");

            var archivo = new Adjunto().Obtener(d.IdAdjunto);
            if (archivo == null) return BadRequest("No se encontró el archivo adjunto.");
            string mime = archivo.Item2;
            if (mime != "image/jpeg" && mime != "image/png" && mime != "image/webp" && mime != "application/pdf")
                return BadRequest("Solo se pueden leer fotos (JPG, PNG, WEBP) o PDF.");

            Compras c = new Compras();
            LectorFactura.Resultado res = await new LectorFactura().Leer(archivo.Item3, mime);

            if (!res.Exito)
            {
                try { c.RegistrarLectura(d.IdAdjunto, id, LectorFactura.Modelo, false, res.Texto, res.Error, res.DuracionMs, null, null, idUsuario); }
                catch (SqlException) { }
                return BadRequest("No se pudo leer la factura. " + res.Error + " Podés cargarla a mano.");
            }

            JObject f = res.Factura;
            var lineas = new List<FacturaLinea>();
            JArray ren = f["renglones"] as JArray;
            if (ren != null)
            {
                int orden = 1;
                foreach (JToken t in ren)
                {
                    lineas.Add(new FacturaLinea
                    {
                        Orden = orden++,
                        Codigo = Texto(t["codigo"]),
                        Descripcion = Texto(t["descripcion"]),
                        Cantidad = Numero(t["cantidad"]),
                        PrecioUnitario = Numero(t["precioUnitario"])
                    });
                }
            }

            try
            {
                DataTable cruce = lineas.Count > 0 ? c.CruzarFactura(id, lineas) : new DataTable();
                int identificados = 0;
                foreach (DataRow row in cruce.Rows)
                    if (row["IdRepuesto"] != DBNull.Value) identificados++;

                int idLectura = c.RegistrarLectura(d.IdAdjunto, id, LectorFactura.Modelo, true, res.Texto, null,
                                                   res.DuracionMs, lineas.Count, identificados, idUsuario);
                return Ok(new
                {
                    IdLectura = idLectura,
                    DuracionMs = res.DuracionMs,
                    Comprobante = new
                    {
                        Proveedor = Texto(f["proveedor"]),
                        TipoComprobante = TipoValido(Texto(f["tipoComprobante"])),
                        Numero = Texto(f["numero"]),
                        Fecha = Texto(f["fecha"]),
                        Total = Numero(f["total"])
                    },
                    Renglones = cruce
                });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "La factura se leyó pero no se pudo cruzar con el pedido.")); }
        }

        private static string Texto(JToken t)
        {
            if (t == null || t.Type == JTokenType.Null) return null;
            string s = t.ToString().Trim();
            return s == "" ? null : s;
        }

        // Acepta 36131.51 y tambien "36.131,51" por si el modelo no respeta el formato
        private static decimal? Numero(JToken t)
        {
            if (t == null || t.Type == JTokenType.Null) return null;
            if (t.Type == JTokenType.Integer || t.Type == JTokenType.Float) return t.Value<decimal>();
            string s = t.ToString().Trim().Replace("$", "").Replace(" ", "");
            if (s.Contains(",")) s = s.Replace(".", "").Replace(",", ".");
            decimal v;
            return decimal.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out v) ? v : (decimal?)null;
        }

        private static string TipoValido(string t)
        {
            string[] validos = { "Factura A", "Factura B", "Factura C", "Presupuesto", "Remito" };
            foreach (string v in validos)
                if (string.Equals(v, t, StringComparison.OrdinalIgnoreCase)) return v;
            return null;
        }


        /* ================= RECLAMOS Y VENCIMIENTOS ================= */

        public class DiasPagoDto { public int DiasPago { get; set; } }
        public class ReclamoDto { public List<int> Ids { get; set; } public string NumeroConstancia { get; set; } }
        public class ResolverDto { public string Accion { get; set; } public string Numero { get; set; } public decimal? Importe { get; set; } public string Motivo { get; set; } }

        // Facturas impagas con su vencimiento (de un proveedor o de todos)
        [HttpGet, Route("api/Compras/Facturas")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public DataTable Facturas(int? idProveedor = null)
        {
            return new Compras().Facturas(idProveedor);
        }

        // Lo que ya se debia, comprobante por comprobante, desde el resumen del proveedor
        [HttpPost, Route("api/Compras/CuentasProveedor/{id:int}/SaldoInicial")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult SaldoInicial(int id, [FromBody] List<SaldoInicialLinea> lineas)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (lineas == null || lineas.Count == 0) return BadRequest("No llegaron comprobantes.");
            try
            {
                DataTable dt = new Compras().SaldoInicial(id, lineas, idUsuario);
                return Ok(new { Cargados = dt.Rows[0]["Cargados"], Total = dt.Rows[0]["Total"] });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo cargar el saldo inicial.")); }
        }

        public class AdjuntoRecepcionDto { public int? IdAdjunto { get; set; } }

        // Cambiar (IdAdjunto) o quitar (null) la foto de una factura
        [HttpPost, Route("api/Compras/Recepcion/{id:int}/Adjunto")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult CambiarAdjunto(int id, [FromBody] AdjuntoRecepcionDto d)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { new Compras().CambiarAdjunto(id, d == null ? null : d.IdAdjunto, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo cambiar la foto.")); }
        }

        [HttpPost, Route("api/Compras/Proveedor/{id:int}/DiasPago")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult DiasPago(int id, [FromBody] DiasPagoDto d)
        {
            if (d == null) return BadRequest("Indicá el plazo.");
            try { new Compras().SetDiasPago(id, d.DiasPago); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo guardar el plazo.")); }
        }

        // Visita del viajante: se le entrega lo reclamado y deja un recibo
        [HttpPost, Route("api/Compras/Incidencias/Reclamar")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Reclamar([FromBody] ReclamoDto d)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (d == null || d.Ids == null || d.Ids.Count == 0) return BadRequest("Elegí qué se le entrega al viajante.");
            try { new Compras().Reclamar(d.Ids, d.NumeroConstancia, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo registrar el reclamo.")); }
        }

        // Llego la nota de credito: baja la deuda y cierra los reclamos que cubre
        [HttpPost, Route("api/Compras/NotasCredito")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult NotaCredito([FromBody] NotaCreditoDto n)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (n == null || n.IdProveedor <= 0) return BadRequest("Faltan los datos de la nota de crédito.");
            try { return Ok(new { IdNotaCredito = new Compras().NotaCredito(n, idUsuario) }); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo registrar la nota de crédito.")); }
        }

        [HttpPost, Route("api/Compras/Incidencias/{id:int}/Resolver")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult Resolver(int id, [FromBody] ResolverDto d)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (d == null || string.IsNullOrWhiteSpace(d.Accion)) return BadRequest("Indicá cómo se resolvió.");
            // Facturar genera deuda: solo quien maneja la plata
            if (d.Accion == "FACTURADO" && !User.IsInRole("Dueño") && !User.IsInRole("Administrador"))
                return BadRequest("Registrar una factura lo hace el Dueño o el Administrador.");
            try { new Compras().ResolverIncidencia(id, d.Accion, d.Numero, d.Importe, d.Motivo, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo cerrar el reclamo.")); }
        }

        /* ================= CUENTA CORRIENTE ================= */

        [HttpGet, Route("api/Compras/CuentasProveedor")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public DataTable Saldos()
        {
            return new Compras().SaldosProveedores();
        }

        [HttpGet, Route("api/Compras/CuentasProveedor/{id:int}")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public DataTable Movimientos(int id)
        {
            return new Compras().MovimientosProveedor(id);
        }

        // Saldo inicial o correccion con motivo
        [HttpPost, Route("api/Compras/CuentasProveedor/{id:int}/Ajuste")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult Ajuste(int id, [FromBody] AjusteDto a)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (a == null || a.Monto == 0) return BadRequest("Indicá el importe del ajuste.");
            try { new Compras().AjusteProveedor(id, a.Monto, a.Motivo, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo registrar el ajuste.")); }
        }

        /* ================= PAGOS ================= */

        [HttpPost, Route("api/Compras/Pagos")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult Pagar([FromBody] PagoProveedorDto p)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (p == null || p.IdProveedor <= 0 || p.IdCuentaFinanciera <= 0) return BadRequest("Faltan el proveedor o la cuenta.");
            if (p.Importe <= 0) return BadRequest("El importe debe ser mayor a cero.");
            try
            {
                DataTable dt = new Compras().Pagar(p, idUsuario);
                return Ok(new { IdPago = dt.Rows[0]["IdPago"], SaldoNuevo = dt.Rows[0]["SaldoNuevo"] });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo registrar el pago.")); }
        }

        [HttpPost, Route("api/Compras/Pagos/{id:int}/Anular")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult AnularPago(int id, [FromBody] MotivoDto m)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { new Compras().AnularPago(id, m == null ? null : m.Motivo, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo anular el pago.")); }
        }

        private string TraducirErrorSql(SqlException ex, string mensajeGenerico)
        {
            if (ex.Number >= 50000) return ex.Message;
            if (ex.Number == 547) return mensajeGenerico + " Algún dato referenciado no existe o no es válido.";
            return mensajeGenerico + " Intentalo de nuevo o avisá a sistemas.";
        }

        private int ObtenerIdUsuarioActual()
        {
            var identity = User.Identity as ClaimsIdentity;
            if (identity == null) return 0;
            var claim = identity.FindFirst(ClaimTypes.NameIdentifier) ?? identity.FindFirst("sub") ?? identity.FindFirst("Sub");
            int id;
            return (claim != null && int.TryParse(claim.Value, out id)) ? id : 0;
        }
    }
}
