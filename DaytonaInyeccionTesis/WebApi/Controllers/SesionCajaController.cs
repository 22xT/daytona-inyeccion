using System;
using System.Collections.Generic;
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
        public class CierreDto
        {
            public decimal EfectivoContado { get; set; }
            public string Motivo { get; set; }
            public List<MedioDeclarado> Medios { get; set; }   // script 94: lo cobrado con cada medio electronico
        }
        public class TextoDto { public string Texto { get; set; } }

        /* Arqueo ciego (script 94): quien atiende el mostrador cierra sin
           ver lo que espera el sistema. El dueño y el administrador lo ven. */
        public static bool VeTeorico(ClaimsIdentity identidad)
        {
            var rol = identidad == null ? null : identidad.FindFirst(ClaimTypes.Role);
            return rol != null && (rol.Value == "Dueño" || rol.Value == "Administrador" || rol.Value == "Analista");
        }

        // GET api/SesionCaja/Actual — si la caja esta abierta y su resumen
        [HttpGet, Route("api/SesionCaja/Actual")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista")]
        public IHttpActionResult Actual()
        {
            DataTable dt = new SesionCaja().Actual(VeTeorico(User.Identity as ClaimsIdentity));
            return Ok(dt.Rows.Count > 0 ? dt : null);
        }

        // GET api/SesionCaja/MediosArqueo — medios a declarar al cerrar (sin importes)
        [HttpGet, Route("api/SesionCaja/MediosArqueo")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataTable MediosArqueo()
        {
            return new SesionCaja().MediosArqueo();
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

        // Cierra con lo contado y devuelve la diferencia (recien ahi se ve)
        [HttpPost, Route("api/SesionCaja/Cerrar")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Cerrar([FromBody] CierreDto c)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (c == null || c.EfectivoContado < 0) return BadRequest("Indicá el efectivo contado.");
            if (c.Medios != null)
                foreach (MedioDeclarado m in c.Medios)
                    if (m == null || m.IdMedioPago <= 0 || m.Declarado < 0)
                        return BadRequest("Lo declarado por medio de pago no es válido.");

            try
            {
                DataSet ds = new SesionCaja().Cerrar(c.EfectivoContado, c.Motivo, idUsuario, c.Medios);
                return Ok(new { Cierre = ds.Tables[0], Medios = ds.Tables.Count > 1 ? ds.Tables[1] : null });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo cerrar la caja.")); }
        }

        // POST api/SesionCaja/5/Explicar — el motivo de la diferencia, despues de cerrar
        [HttpPost, Route("api/SesionCaja/{id:int}/Explicar")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Explicar(int id, [FromBody] TextoDto t)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { new SesionCaja().Explicar(id, t == null ? null : t.Texto, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo guardar el motivo.")); }
        }

        // POST api/SesionCaja/5/Aprobar — el supervisor revisa la diferencia
        [HttpPost, Route("api/SesionCaja/{id:int}/Aprobar")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult Aprobar(int id, [FromBody] TextoDto t)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { new SesionCaja().Aprobar(id, t == null ? null : t.Texto, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo aprobar.")); }
        }

        // GET api/SesionCaja/5/Resumen — resumen del turno cerrado
        [HttpGet, Route("api/SesionCaja/{id:int}/Resumen")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista")]
        public IHttpActionResult Resumen(int id)
        {
            try
            {
                DataSet ds = new SesionCaja().Resumen(id);
                if (ds.Tables.Count < 6) return NotFound();
                return Ok(new
                {
                    Sesion = ds.Tables[0], Efectivo = ds.Tables[1], Medios = ds.Tables[2],
                    Ventas = ds.Tables[3], Cobrado = ds.Tables[4], Comprobantes = ds.Tables[5]
                });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo armar el resumen.")); }
        }

        [HttpGet, Route("api/SesionCaja/Historial")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public DataTable Historial(DateTime? desde = null, DateTime? hasta = null)
        {
            return new SesionCaja().Historial(desde, hasta);
        }

        [HttpGet, Route("api/SesionCaja/Diferencias")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
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
