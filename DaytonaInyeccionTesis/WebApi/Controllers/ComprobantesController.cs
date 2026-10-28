using System;
using System.Data;
using System.Data.SqlClient;
using System.Security.Claims;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    /* Comprobantes fiscales (script 92). Se generan solos al registrar
       una venta o una nota; desde aca se consultan y se generan los que
       quedaron pendientes (por ejemplo, un cliente inscripto sin CUIT). */
    [AuthorizeJwt]
    public class ComprobantesController : ApiController
    {
        // GET api/Comprobantes?desde=&hasta=&estado=&clase=
        [HttpGet, Route("api/Comprobantes")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public IHttpActionResult Listar(DateTime? desde = null, DateTime? hasta = null, string estado = null, string clase = null)
        {
            if (desde.HasValue && hasta.HasValue && desde.Value.Date > hasta.Value.Date)
                return BadRequest("La fecha desde no puede ser posterior a la fecha hasta.");
            try { return Ok(new Comprobante().Listar(desde, hasta, estado, clase)); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudieron leer los comprobantes.")); }
        }

        // GET api/Comprobantes/5
        [HttpGet, Route("api/Comprobantes/{id:int}")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista")]
        public IHttpActionResult Obtener(int id)
        {
            DataSet ds = new Comprobante().Obtener(id);
            if (ds.Tables.Count < 4 || ds.Tables[0].Rows.Count == 0) return NotFound();
            DataTable emisor = new Comprobante().Emisor();
            DataRow c = ds.Tables[0].Rows[0];
            string qr = null;
            if (Convert.ToString(c["Estado"]) == "AUTORIZADO" && emisor.Rows.Count > 0)
                qr = ArcaEmision.QrUrl(c, Convert.ToString(emisor.Rows[0]["Cuit"]));
            return Ok(new { Comprobante = ds.Tables[0], Renglones = ds.Tables[1], Iva = ds.Tables[2], Notas = ds.Tables[3],
                            Emisor = emisor, Qr = qr });
        }

        // POST api/Comprobantes/5/Autorizar — pide el CAE a ARCA
        [HttpPost, Route("api/Comprobantes/{id:int}/Autorizar")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult Autorizar(int id)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { return Ok(new ArcaEmision().Autorizar(id, idUsuario)); }
            catch (ArcaException ex) { return BadRequest(ex.Message); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo pedir el CAE.")); }
            catch (System.Security.Cryptography.CryptographicException)
            {
                return BadRequest("No se pudo usar el certificado de ARCA: revisá el archivo .pfx y su clave en la configuración.");
            }
        }

        // POST api/Comprobantes/5/Rehacer — anula un borrador o rechazado y lo genera de nuevo
        [HttpPost, Route("api/Comprobantes/{id:int}/Rehacer")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult Rehacer(int id)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { return Ok(Primera(new Comprobante().Rehacer(id, idUsuario))); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo rehacer el comprobante.")); }
        }

        // GET api/Comprobantes/5/Arca — lo que se le pidio a ARCA y que contesto
        [HttpGet, Route("api/Comprobantes/{id:int}/Arca")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult HistorialArca(int id)
        {
            return Ok(new Comprobante().HistorialArca(id));
        }

        // GET api/Arca/Estado — prueba la conexion paso a paso
        [HttpGet, Route("api/Arca/Estado")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult EstadoArca()
        {
            try { return Ok(new ArcaEmision().Estado()); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo leer la configuración de ARCA.")); }
        }

        // GET api/Comprobantes/Pendientes — ventas y notas sin comprobante
        [HttpGet, Route("api/Comprobantes/Pendientes")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public IHttpActionResult Pendientes()
        {
            try { return Ok(new Comprobante().Pendientes()); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudieron leer los pendientes.")); }
        }

        // POST api/Comprobantes/DesdeVenta/5
        [HttpPost, Route("api/Comprobantes/DesdeVenta/{idVenta:int}")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult DesdeVenta(int idVenta)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { return Ok(Primera(new Comprobante().DesdeVenta(idVenta, idUsuario))); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo generar la factura.")); }
        }

        // POST api/Comprobantes/DesdeNota/5
        [HttpPost, Route("api/Comprobantes/DesdeNota/{idNota:int}")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult DesdeNota(int idNota)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { return Ok(Primera(new Comprobante().DesdeNota(idNota, idUsuario))); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo generar la nota.")); }
        }

        private static object Primera(DataTable dt)
        {
            if (dt == null || dt.Rows.Count == 0) return null;
            DataRow r = dt.Rows[0];
            return new
            {
                IdComprobante = Convert.ToInt32(r["IdComprobante"]),
                Tipo = Convert.ToString(r["Tipo"]),
                Estado = Convert.ToString(r["Estado"]),
                Total = Convert.ToDecimal(r["ImporteTotal"]),
                Nuevo = Convert.ToBoolean(r["Nuevo"])
            };
        }

        private string TraducirErrorSql(SqlException ex, string mensajeGenerico)
        {
            if (ex.Number >= 50000) return ex.Message;
            if (ex.Number == 2601 || ex.Number == 2627) return "Ya existe un comprobante vigente para esa operación.";
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
