using System;
using System.Data;
using System.Data.SqlClient;
using System.Security.Claims;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;
using System.IdentityModel.Tokens.Jwt;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class MovimientoStockController : ApiController
    {
        // GET: api/MovimientoStock  (historial completo)
        [AuthorizeJwt(Roles = "Administrador,Analista,Dueño,Vendedor")]
        public DataTable Get()
        {
            MovimientoStock oMov = new MovimientoStock();
            return oMov.ListarTodos();
        }

        // GET: api/MovimientoStock/5  (historial de un repuesto)
        [AuthorizeJwt(Roles = "Administrador,Analista,Dueño,Vendedor")]
        public DataTable Get(int id)
        {
            MovimientoStock oMov = new MovimientoStock();
            oMov.IdRepuesto = id;
            return oMov.ListarPorRepuesto();
        }

        // POST: api/MovimientoStock  — Admin, Analista y Vendedor
        [AuthorizeJwt(Roles = "Administrador,Analista,Vendedor")]
        public IHttpActionResult Post([FromBody] MovimientoStock mov)
        {
            string error = Validar(mov);
            if (error != "")
                return BadRequest(error);

            // Sacar el IdUsuario del token (claim Sub)
            int idUsuario = ObtenerIdUsuario();
            if (idUsuario == 0)
                return BadRequest("No se pudo identificar al usuario de la sesión.");

            mov.IdUsuario = idUsuario;

            try
            {
                mov.Ajustar();
            }
            catch (SqlException ex)
            {
                // Los RAISERROR del SP llegan acá con su mensaje
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

        private string Validar(MovimientoStock mov)
        {
            if (mov == null)
                return "No se recibieron datos del ajuste.";

            if (mov.IdRepuesto <= 0)
                return "Debe seleccionar un repuesto válido.";

            if (mov.CantidadNueva < 0)
                return "La cantidad nueva no puede ser negativa.";

            if (string.IsNullOrWhiteSpace(mov.Tipo))
                return "Debe indicar el tipo de ajuste.";

            if (string.IsNullOrWhiteSpace(mov.Motivo))
                return "El motivo del ajuste es obligatorio.";

            if (mov.Motivo.Length > 250)
                return "El motivo no puede superar los 250 caracteres.";

            return "";
        }
    }
}