using System;
using System.Data;
using System.Data.SqlClient;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class MovimientoCajaController : ApiController
    {
        // GET: api/MovimientoCaja  (historial) — Admin, Vendedor, Dueño
        [AuthorizeJwt(Roles = "Administrador,Vendedor,Dueño")]
        public DataTable Get()
        {
            MovimientoCaja oCaja = new MovimientoCaja();
            return oCaja.ListarTodos();
        }

        // GET: api/MovimientoCaja/Saldo  (saldo actual + totales del dia)
        [HttpGet]
        [Route("api/MovimientoCaja/Saldo")]
        [AuthorizeJwt(Roles = "Administrador,Vendedor,Dueño")]
        public DataTable GetSaldo()
        {
            MovimientoCaja oCaja = new MovimientoCaja();
            return oCaja.ObtenerSaldo();
        }

        // POST: api/MovimientoCaja  (registrar) — Admin y Vendedor
        [AuthorizeJwt(Roles = "Administrador,Vendedor")]
        public IHttpActionResult Post([FromBody] MovimientoCaja mov)
        {
            string error = Validar(mov);
            if (error != "")
                return BadRequest(error);

            int idUsuario = ObtenerIdUsuario();
            if (idUsuario == 0)
                return BadRequest("No se pudo identificar al usuario de la sesión.");

            mov.IdUsuario = idUsuario;

            try
            {
                mov.Registrar();
            }
            catch (SqlException ex)
            {
                return BadRequest(ex.Message);
            }

            return Ok();
        }

        private int ObtenerIdUsuario()
        {
            var identity = User.Identity as ClaimsIdentity;
            if (identity == null) return 0;

            var claim = identity.FindFirst(ClaimTypes.NameIdentifier)
                        ?? identity.FindFirst(JwtRegisteredClaimNames.Sub)
                        ?? identity.FindFirst("sub");

            if (claim == null) return 0;

            int id;
            return int.TryParse(claim.Value, out id) ? id : 0;
        }

        private string Validar(MovimientoCaja mov)
        {
            if (mov == null)
                return "No se recibieron datos del movimiento.";

            if (string.IsNullOrWhiteSpace(mov.Tipo) || (mov.Tipo != "Ingreso" && mov.Tipo != "Egreso"))
                return "El tipo debe ser Ingreso o Egreso.";

            if (string.IsNullOrWhiteSpace(mov.Concepto))
                return "El concepto es obligatorio.";

            if (mov.Monto <= 0)
                return "El monto debe ser mayor a cero.";

            if (mov.Descripcion != null && mov.Descripcion.Length > 250)
                return "La descripción no puede superar los 250 caracteres.";

            return "";
        }
    }
}