using System;
using System.Data;
using System.Data.SqlClient;
using System.Security.Claims;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    /* Encargos con seña. Los toma y los entrega el mostrador, asi que
       los vendedores tienen acceso completo. La entrega no esta aca:
       es una venta comun (api/Venta) con IdEncargo. */
    [AuthorizeJwt]
    public class EncargosController : ApiController
    {
        private const string ROLES = "Dueño,Administrador,Supervisor,Vendedor";

        // GET api/Encargos?abiertos=true — listado con disponibilidad y total de señas
        [HttpGet, Route("api/Encargos")]
        [AuthorizeJwt(Roles = ROLES)]
        public IHttpActionResult Listar(bool abiertos = true)
        {
            DataSet ds = new Encargo().Listar(abiertos);
            return Ok(new
            {
                Encargos = ds.Tables[0],
                SenasPendientes = ds.Tables.Count > 1 && ds.Tables[1].Rows.Count > 0 ? ds.Tables[1].Rows[0]["SenasPendientes"] : 0
            });
        }

        // GET api/Encargos/5 — cabecera, renglones con stock y señas
        [HttpGet, Route("api/Encargos/{id:int}")]
        [AuthorizeJwt(Roles = ROLES)]
        public IHttpActionResult Obtener(int id)
        {
            DataSet ds = new Encargo().Obtener(id);
            if (ds.Tables.Count < 3 || ds.Tables[0].Rows.Count == 0) return NotFound();
            return Ok(new { Encargo = ds.Tables[0], Renglones = ds.Tables[1], Senas = ds.Tables[2] });
        }

        [HttpPost, Route("api/Encargos")]
        [AuthorizeJwt(Roles = ROLES)]
        public IHttpActionResult Crear([FromBody] EncargoDto d)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (d == null || d.Lineas == null || d.Lineas.Count == 0) return BadRequest("Indicá qué repuesto encarga.");
            try
            {
                DataRow r = new Encargo().Crear(d, idUsuario);
                return Ok(new { IdEncargo = r["IdEncargo"], IdPedido = r["IdPedido"], LlegadaEstimada = r["LlegadaEstimada"] });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo tomar el encargo.")); }
        }

        [HttpPost, Route("api/Encargos/{id:int}/Sena")]
        [AuthorizeJwt(Roles = ROLES)]
        public IHttpActionResult AgregarSena(int id, [FromBody] EncargoSenaDto d)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (d == null || d.Monto <= 0 || d.IdMedioPago <= 0) return BadRequest("Indicá el importe y el medio de la seña.");
            try { new Encargo().AgregarSena(id, d, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo registrar la seña.")); }
        }

        [HttpPost, Route("api/Encargos/{id:int}/Avisado")]
        [AuthorizeJwt(Roles = ROLES)]
        public IHttpActionResult Avisado(int id)
        {
            try { new Encargo().MarcarAvisado(id); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo marcar el aviso.")); }
        }

        [HttpPost, Route("api/Encargos/{id:int}/Cancelar")]
        [AuthorizeJwt(Roles = ROLES)]
        public IHttpActionResult Cancelar(int id, [FromBody] EncargoCancelarDto d)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (d == null) return BadRequest("Indicá el motivo de la cancelación.");
            try { new Encargo().Cancelar(id, d, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo cancelar el encargo.")); }
        }

        // GET api/Encargos/ParaSeparar?idPedido=5 — al recibir, a quien hay que avisar
        [HttpGet, Route("api/Encargos/ParaSeparar")]
        [AuthorizeJwt(Roles = ROLES)]
        public DataTable ParaSeparar(int idPedido)
        {
            return new Encargo().ParaSeparar(idPedido);
        }

        // GET api/Encargos/Reservas — stock apartado para encargos, por repuesto
        [HttpGet, Route("api/Encargos/Reservas")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista")]
        public DataTable Reservas()
        {
            return new Encargo().Reservas();
        }

        // Cuentas desde las que se puede devolver una seña
        [HttpGet, Route("api/Encargos/Cuentas")]
        [AuthorizeJwt(Roles = ROLES)]
        public DataTable Cuentas()
        {
            return new MovimientoEspecial().CuentasDisponibles();
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
