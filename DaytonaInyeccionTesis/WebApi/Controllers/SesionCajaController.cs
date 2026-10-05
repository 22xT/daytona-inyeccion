using System;
using System.Data;
using System.Data.SqlClient;
using System.Security.Claims;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class SesionCajaController : ApiController
    {
        public class AperturaDto { public decimal SaldoInicial { get; set; } public string Motivo { get; set; } }
        public class CierreDto   { public decimal EfectivoContado { get; set; } public string Motivo { get; set; } }

        // GET api/SesionCaja/Actual — si la caja esta abierta y su resumen
        [HttpGet, Route("api/SesionCaja/Actual")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista")]
        public IHttpActionResult Actual()
        {
            DataTable dt = new SesionCaja().Actual();
            return Ok(dt.Rows.Count > 0 ? dt : null);
        }

        [HttpPost, Route("api/SesionCaja/Abrir")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Abrir([FromBody] AperturaDto a)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (a == null || a.SaldoInicial < 0) return BadRequest("Indicá el efectivo con que arranca la caja.");

            try { return Ok(new SesionCaja().Abrir(a.SaldoInicial, a.Motivo, idUsuario)); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo abrir la caja.")); }
        }

        [HttpPost, Route("api/SesionCaja/Cerrar")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Cerrar([FromBody] CierreDto c)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (c == null || c.EfectivoContado < 0) return BadRequest("Indicá el efectivo contado.");

            try { return Ok(new SesionCaja().Cerrar(c.EfectivoContado, c.Motivo, idUsuario)); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo cerrar la caja.")); }
        }

        [HttpGet, Route("api/SesionCaja/Historial")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public DataTable Historial(DateTime? desde = null, DateTime? hasta = null)
        {
            return new SesionCaja().Historial(desde, hasta);
        }

        [HttpGet, Route("api/SesionCaja/Diferencias")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Analista")]
        public DataTable Diferencias(DateTime? desde = null, DateTime? hasta = null)
        {
            return new SesionCaja().ResumenDiferencias(desde, hasta);
        }

        private string TraducirErrorSql(SqlException ex, string mensajeGenerico)
        {
            if (ex.Number >= 50000) return ex.Message;
            if (ex.Number == 2601 || ex.Number == 2627) return "La caja ya está abierta.";
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
