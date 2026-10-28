using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.Security.Claims;
using System.Threading.Tasks;
using System.Web.Http;
using Newtonsoft.Json.Linq;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    /* Pagos a proveedores (script 95): ordenes de pago y datos fiscales
       de las facturas de compra. La plata la manejan Dueño y Administrador. */
    [AuthorizeJwt]
    public class OrdenesPagoController : ApiController
    {
        public class MotivoDto { public string Motivo { get; set; } }
        public class AdjuntoDto { public int IdAdjunto { get; set; } }

        /* ================= ORDENES DE PAGO ================= */

        [HttpGet, Route("api/Compras/OrdenesPago")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public DataTable Listar(int? idProveedor = null, DateTime? desde = null, DateTime? hasta = null)
        {
            return new OrdenPago().Listar(idProveedor, desde, hasta);
        }

        [HttpGet, Route("api/Compras/OrdenesPago/{id:int}")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public IHttpActionResult Obtener(int id)
        {
            DataSet ds = new OrdenPago().Obtener(id);
            if (ds.Tables.Count < 4 || ds.Tables[0].Rows.Count == 0) return NotFound();
            return Ok(new { Orden = ds.Tables[0], Facturas = ds.Tables[1], NotasCredito = ds.Tables[2], Medios = ds.Tables[3] });
        }

        // Notas de credito con saldo para aplicar
        [HttpGet, Route("api/Compras/Proveedor/{id:int}/NotasCreditoDisponibles")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public DataTable NotasCreditoDisponibles(int id)
        {
            return new OrdenPago().NotasCreditoDisponibles(id);
        }

        [HttpPost, Route("api/Compras/OrdenesPago")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult Registrar([FromBody] OrdenPagoDto d)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (d == null || d.IdProveedor <= 0) return BadRequest("Falta el proveedor.");
            if (d.Facturas == null || d.Facturas.Count == 0) return BadRequest("Elegí qué facturas se pagan.");
            try
            {
                DataTable dt = new OrdenPago().Registrar(d, idUsuario);
                return Ok(new { IdOrdenPago = dt.Rows[0]["IdOrdenPago"], SaldoNuevo = dt.Rows[0]["SaldoNuevo"] });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo registrar la orden de pago.")); }
        }

        [HttpPost, Route("api/Compras/OrdenesPago/{id:int}/Anular")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult Anular(int id, [FromBody] MotivoDto m)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { new OrdenPago().Anular(id, m == null ? null : m.Motivo, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo anular la orden de pago.")); }
        }

        /* ================= DATOS FISCALES DE LA COMPRA ================= */

        [HttpGet, Route("api/Compras/DatosFiscales/{idMovimiento:int}")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public IHttpActionResult FiscalObtener(int idMovimiento)
        {
            DataSet ds = new OrdenPago().FiscalObtener(idMovimiento);
            if (ds.Tables.Count < 2 || ds.Tables[0].Rows.Count == 0) return NotFound();
            return Ok(new { Comprobante = ds.Tables[0], Iva = ds.Tables[1] });
        }

        [HttpGet, Route("api/Compras/DatosFiscales")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public DataTable FiscalEstado(int idProveedor)
        {
            return new OrdenPago().FiscalEstado(idProveedor);
        }

        [HttpPost, Route("api/Compras/DatosFiscales/{idMovimiento:int}")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult FiscalGuardar(int idMovimiento, [FromBody] CompraFiscalDto d)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (d == null) return BadRequest("Faltan los datos del comprobante.");
            try { new OrdenPago().FiscalGuardar(idMovimiento, d, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudieron guardar los datos fiscales.")); }
        }

        /* POST api/Compras/DatosFiscales/Leer { IdAdjunto }
           Lee los datos fiscales de la foto o el PDF con IA. Es una
           propuesta: se muestra en el formulario para revisar. */
        [HttpPost, Route("api/Compras/DatosFiscales/Leer")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public async Task<IHttpActionResult> FiscalLeer([FromBody] AdjuntoDto d)
        {
            if (!LectorFactura.Configurado)
                return BadRequest("La lectura automática no está configurada en el servidor. Cargá los datos a mano.");
            if (d == null || d.IdAdjunto <= 0) return BadRequest("El comprobante no tiene foto o PDF adjunto.");

            var archivo = new Adjunto().Obtener(d.IdAdjunto);
            if (archivo == null) return BadRequest("No se encontró el archivo adjunto.");
            string mime = archivo.Item2;
            if (mime != "image/jpeg" && mime != "image/png" && mime != "image/webp" && mime != "application/pdf")
                return BadRequest("Solo se pueden leer fotos (JPG, PNG, WEBP) o PDF.");

            LectorFactura.Resultado res = await new LectorFactura().Leer(archivo.Item3, mime, LectorFactura.InstruccionesFiscales);
            if (!res.Exito) return BadRequest("No se pudo leer el comprobante. " + res.Error);

            JObject f = res.Factura;
            // Tipo de ARCA desde letra y clase
            string letra = Texto(f["letra"]), clase = Texto(f["clase"]);
            int? tipo = null;
            if (letra != null && clase != null)
            {
                int baseLetra = letra == "A" ? 1 : letra == "B" ? 6 : letra == "C" ? 11 : 0;
                int extra = clase == "FACTURA" ? 0 : clase == "NOTA_DEBITO" ? 1 : clase == "NOTA_CREDITO" ? 2 : -1;
                if (baseLetra > 0 && extra >= 0) tipo = baseLetra + extra;
            }
            var iva = new List<object>();
            JArray arr = f["iva"] as JArray;
            if (arr != null)
                foreach (JToken t in arr)
                {
                    decimal? alic = Numero(t["alicuota"]);
                    int? id = alic == 21m ? 5 : alic == 10.5m ? 4 : alic == 27m ? 6 : alic == 5m ? 8 : alic == 2.5m ? 9 : alic == 0m ? (int?)3 : null;
                    if (id.HasValue) iva.Add(new { IdArcaIva = id.Value, BaseImponible = Numero(t["neto"]), Importe = Numero(t["importe"]) });
                }

            return Ok(new
            {
                CuitEmisor = Texto(f["cuitEmisor"]),
                TipoArca = tipo,
                PuntoVenta = Numero(f["puntoVenta"]),
                Numero = Numero(f["numero"]),
                Fecha = Texto(f["fecha"]),
                Cae = Texto(f["cae"]),
                CaeVencimiento = Texto(f["caeVencimiento"]),
                Iva = iva,
                ImporteNoGravado = Numero(f["noGravado"]),
                ImporteExento = Numero(f["exento"]),
                PercepcionIva = Numero(f["percepcionIva"]),
                PercepcionIibb = Numero(f["percepcionIibb"]),
                ImpuestosInternos = Numero(f["impuestosInternos"]),
                OtrosTributos = Numero(f["otrosTributos"]),
                ImporteTotal = Numero(f["total"])
            });
        }

        private static string Texto(JToken t)
        {
            if (t == null || t.Type == JTokenType.Null) return null;
            string s = t.ToString().Trim();
            return s == "" ? null : s;
        }

        private static decimal? Numero(JToken t)
        {
            if (t == null || t.Type == JTokenType.Null) return null;
            if (t.Type == JTokenType.Integer || t.Type == JTokenType.Float) return t.Value<decimal>();
            decimal d;
            return decimal.TryParse(t.ToString().Replace(",", "."), NumberStyles.Any, CultureInfo.InvariantCulture, out d) ? d : (decimal?)null;
        }

        private string TraducirErrorSql(SqlException ex, string mensajeGenerico)
        {
            if (ex.Number >= 50000) return ex.Message;
            if (ex.Number == 2601 || ex.Number == 2627) return "Ese comprobante ya está cargado.";
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
