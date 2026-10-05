using System;
using System.Data;
using System.Data.SqlClient;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    /* Etapa 1 de Caja y Finanzas.
       Reemplaza el alta libre de ingresos y egresos: todo dinero que se
       mueve a mano pasa por un gasto con comprobante o por un movimiento
       especial de una lista cerrada. */
    [AuthorizeJwt]
    public class FinanzasController : ApiController
    {
        public class ArchivoDto
        {
            public string NombreArchivo { get; set; }
            public string TipoMime { get; set; }
            public string ContenidoBase64 { get; set; }
        }

        public class MotivoDto
        {
            public string Motivo { get; set; }
        }

        public class PagoGastoDto
        {
            public int IdCuentaFinanciera { get; set; }
        }

        /* ================= CUENTAS ================= */

        // GET api/Finanzas/Cuentas — cuentas donde se puede pagar o mover dinero
        [HttpGet, Route("api/Finanzas/Cuentas")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Analista")]
        public DataTable Cuentas()
        {
            return new MovimientoEspecial().CuentasDisponibles();
        }

        /* ================= ADJUNTOS ================= */

        // POST api/Finanzas/Adjunto — sube la foto o el PDF del comprobante, devuelve el Id
        [HttpPost, Route("api/Finanzas/Adjunto")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult SubirAdjunto([FromBody] ArchivoDto a)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (a == null || string.IsNullOrWhiteSpace(a.ContenidoBase64))
                return BadRequest("No llegó ningún archivo.");

            byte[] bytes;
            try
            {
                // Acepta con o sin el prefijo "data:...;base64,"
                string b64 = a.ContenidoBase64;
                int coma = b64.IndexOf(',');
                if (b64.StartsWith("data:") && coma > 0) b64 = b64.Substring(coma + 1);
                bytes = Convert.FromBase64String(b64);
            }
            catch (FormatException) { return BadRequest("El archivo llegó dañado."); }

            if (bytes.Length > 2097152)
                return BadRequest("El archivo supera los 2 MB.");

            try
            {
                int id = new Adjunto().Guardar(a.NombreArchivo ?? "comprobante", a.TipoMime ?? "", bytes, idUsuario);
                return Ok(new { IdAdjunto = id });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo guardar el archivo.")); }
        }

        // GET api/Finanzas/Adjunto/5 — descarga el comprobante
        [HttpGet, Route("api/Finanzas/Adjunto/{id:int}")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public HttpResponseMessage VerAdjunto(int id)
        {
            var a = new Adjunto().Obtener(id);
            if (a == null) return Request.CreateResponse(HttpStatusCode.NotFound);

            var resp = new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(a.Item3) };
            resp.Content.Headers.ContentType = new MediaTypeHeaderValue(a.Item2);
            resp.Content.Headers.ContentDisposition = new ContentDispositionHeaderValue("inline") { FileName = a.Item1 };
            return resp;
        }

        /* ================= GASTOS ================= */

        [HttpGet, Route("api/Finanzas/TiposGasto")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Analista")]
        public DataTable TiposGasto()
        {
            return new Gasto().Tipos();
        }

        [HttpGet, Route("api/Finanzas/Gastos")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Analista")]
        public DataTable Gastos(DateTime? desde = null, DateTime? hasta = null, string estado = null)
        {
            return new Gasto().Listar(desde, hasta, estado);
        }

        [HttpGet, Route("api/Finanzas/Gastos/Resumen")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Analista")]
        public DataTable ResumenGastos(DateTime? desde = null, DateTime? hasta = null)
        {
            return new Gasto().Resumen(desde, hasta);
        }

        [HttpPost, Route("api/Finanzas/Gastos")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult RegistrarGasto([FromBody] Gasto g)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (g == null) return BadRequest("Faltan los datos del gasto.");
            if (g.Importe <= 0) return BadRequest("El importe debe ser mayor a cero.");

            try
            {
                DataTable r = g.Registrar(idUsuario);
                return Ok(new { IdGasto = r.Rows[0]["IdGasto"], Estado = r.Rows[0]["Estado"] });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo registrar el gasto.")); }
        }

        [HttpPost, Route("api/Finanzas/Gastos/{id:int}/Pagar")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult PagarGasto(int id, [FromBody] PagoGastoDto p)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (p == null || p.IdCuentaFinanciera <= 0) return BadRequest("Elegí la cuenta con la que se paga.");

            try { new Gasto().Pagar(id, p.IdCuentaFinanciera, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo pagar el gasto.")); }
        }

        [HttpPost, Route("api/Finanzas/Gastos/{id:int}/AnularPago")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult AnularPagoGasto(int id, [FromBody] MotivoDto m)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { new Gasto().AnularPago(id, m == null ? null : m.Motivo, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo anular el pago.")); }
        }

        [HttpPost, Route("api/Finanzas/Gastos/{id:int}/Anular")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult AnularGasto(int id, [FromBody] MotivoDto m)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { new Gasto().Anular(id, m == null ? null : m.Motivo, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo anular el gasto.")); }
        }

        /* ================= MOVIMIENTOS ESPECIALES ================= */

        [HttpGet, Route("api/Finanzas/MovimientosEspeciales")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Analista")]
        public DataTable MovimientosEspeciales(DateTime? desde = null, DateTime? hasta = null)
        {
            return new MovimientoEspecial().Listar(desde, hasta);
        }

        [HttpPost, Route("api/Finanzas/MovimientosEspeciales")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult RegistrarMovimientoEspecial([FromBody] MovimientoEspecial m)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (m == null || string.IsNullOrWhiteSpace(m.Tipo)) return BadRequest("Elegí el tipo de movimiento.");

            // Aportes y retiros son plata del dueño: solo el Dueño los registra
            string tipo = m.Tipo.Trim().ToUpperInvariant();
            if ((tipo == "APORTE" || tipo == "RETIRO") && !EsRol("Dueño"))
                return Content(HttpStatusCode.Forbidden, "Solo el Dueño puede registrar aportes y retiros.");

            try
            {
                m.Tipo = tipo;
                int id = m.Registrar(idUsuario);
                return Ok(new { Id = id });
            }
            catch (SqlException ex)
            {
                // Violacion del CHECK de cuentas por tipo
                if (ex.Number == 547)
                    return BadRequest("Las cuentas no corresponden al tipo: un aporte o un rendimiento llevan solo destino, un retiro solo origen, una transferencia las dos (distintas), un ajuste una sola.");
                return BadRequest(TraducirErrorSql(ex, "No se pudo registrar el movimiento."));
            }
        }

        [HttpPost, Route("api/Finanzas/MovimientosEspeciales/{id:int}/Anular")]
        [AuthorizeJwt(Roles = "Dueño")]
        public IHttpActionResult AnularMovimientoEspecial(int id, [FromBody] MotivoDto m)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { new MovimientoEspecial().Anular(id, m == null ? null : m.Motivo, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo anular el movimiento.")); }
        }

        /* ================= AUXILIARES ================= */

        private bool EsRol(string rol)
        {
            var identity = User.Identity as ClaimsIdentity;
            if (identity == null) return false;
            foreach (var c in identity.FindAll(ClaimTypes.Role))
                if (string.Equals(c.Value, rol, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
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
            var claim = identity.FindFirst(ClaimTypes.NameIdentifier)
                     ?? identity.FindFirst("sub")
                     ?? identity.FindFirst("Sub");
            int id;
            return (claim != null && int.TryParse(claim.Value, out id)) ? id : 0;
        }
    }
}
