using System.Data;
using System.Data.SqlClient;
using System.Security.Claims;
using System.Text.RegularExpressions;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    public class SolicitudResetController : ApiController
    {
        [AllowAnonymous]
        [HttpPost]
        [Route("api/SolicitudReset")]
        public IHttpActionResult Post([FromBody] SolicitudReset solicitud)
        {
            if (solicitud == null)
                return BadRequest("No se recibieron datos.");

            // Validar correo
            if (string.IsNullOrWhiteSpace(solicitud.Correo))
                return BadRequest("El correo es obligatorio.");

            if (!Regex.IsMatch(solicitud.Correo, @"^[^@\s]+@[^@\s]+\.[^@\s]+$"))
                return BadRequest("El correo no es válido.");

            // Limitar el mensaje
            if (!string.IsNullOrWhiteSpace(solicitud.Mensaje) && solicitud.Mensaje.Length > 500)
                return BadRequest("El mensaje no puede superar los 500 caracteres.");

            try
            {
                int id = solicitud.Guardar();
                return Ok(new { Id = id, Mensaje = "Solicitud registrada correctamente." });
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo registrar la solicitud. " + ex.Message);
            }
        }

        // GET: api/SolicitudReset/Pendientes  (solo Administrador)
        [AuthorizeJwt(Roles = "Administrador")]
        [HttpGet]
        [Route("api/SolicitudReset/Pendientes")]
        public DataTable GetPendientes()
        {
            SolicitudReset oSol = new SolicitudReset();
            return oSol.ListarPendientes();
        }

        // GET: api/SolicitudReset  (solo Administrador) 
        [AuthorizeJwt(Roles = "Administrador")]
        public DataTable Get()
        {
            SolicitudReset oSol = new SolicitudReset();
            return oSol.ListarTodos();
        }

        // PUT: api/SolicitudReset/5/Procesar?estado=Procesada  (solo Administrador)
        [AuthorizeJwt(Roles = "Administrador")]
        [HttpPut]
        [Route("api/SolicitudReset/{id:int}/Procesar")]
        public IHttpActionResult Procesar(int id, string estado = "Procesada")
        {
            // Validar estado
            if (estado != "Procesada" && estado != "Descartada")
                return BadRequest("Estado inválido. Solo 'Procesada' o 'Descartada'.");

            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario == 0)
                return BadRequest("No se pudo identificar al usuario administrador.");

            SolicitudReset oSol = new SolicitudReset();
            oSol.Id = id;

            try
            {
                oSol.Procesar(idUsuario, estado);
                return Ok();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo procesar la solicitud. " + ex.Message);
            }
        }

        // Lee el Id del usuario logueado desde el claim Sub del JWT
        private int ObtenerIdUsuarioActual()
        {
            var identity = User.Identity as ClaimsIdentity;
            if (identity == null) return 0;

            var claim = identity.FindFirst("sub")
                     ?? identity.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)
                     ?? identity.FindFirst(ClaimTypes.NameIdentifier);

            int id;
            if (claim != null && int.TryParse(claim.Value, out id))
                return id;
            return 0;
        }
    }
}