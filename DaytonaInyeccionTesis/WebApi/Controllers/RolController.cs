using System.Data;
using System.Data.SqlClient;
using System.Web.Http;
using WebApi.Models;
using WebApi.Filters;

namespace WebApi.Controllers
{
    [AuthorizeJwt(Roles = "Administrador")] // todo el controller solo Admin
    public class RolController : ApiController
    {
        // GET: api/Rol  (solo Administrador)
        public DataTable Get()
        {
            Rol oRol = new Rol();
            return oRol.ListarTodos();
        }

        // GET: api/Rol/5  (solo Administrador)
        public DataTable Get(int id)
        {
            Rol oRol = new Rol();
            oRol.Id = id;
            return oRol.ListarPorId();
        }

        // POST: api/Rol  (solo Administrador)
        public IHttpActionResult Post([FromBody] Rol rol)
        {
            string error = ValidarRol(rol);
            if (error != "")
                return BadRequest(error);

            try
            {
                rol.Guardar();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe un rol con ese nombre.");

                return BadRequest("No se pudo guardar el rol. " + ex.Message);
            }

            return Ok();
        }

        // PUT: api/Rol/5  (solo Administrador)
        public IHttpActionResult Put(int id, [FromBody] Rol rol)
        {
            string error = ValidarRol(rol);
            if (error != "")
                return BadRequest(error);

            rol.Id = id;

            try
            {
                rol.Editar();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe un rol con ese nombre.");

                return BadRequest("No se pudo editar el rol. " + ex.Message);
            }

            return Ok();
        }

        // DELETE: api/Rol/5  (solo Administrador)
        public IHttpActionResult Delete(int id)
        {
            Rol oRol = new Rol();
            oRol.Id = id;

            try
            {
                oRol.Eliminar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo dar de baja el rol. " + ex.Message);
            }

            return Ok();
        }

        // PUT: api/Rol/5/Activar  (solo Administrador)
        [HttpPut]
        [Route("api/Rol/{id:int}/Activar")]
        public IHttpActionResult Activar(int id)
        {
            Rol oRol = new Rol();
            oRol.Id = id;

            try
            {
                oRol.Activar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo activar el rol. " + ex.Message);
            }

            return Ok();
        }

        // Valida los datos del rol. Devuelve "" si esta todo bien.
        private string ValidarRol(Rol rol)
        {
            if (rol == null)
                return "No se recibieron datos del rol.";

            // Nombre: obligatorio
            if (string.IsNullOrWhiteSpace(rol.Nombre))
                return "El nombre del rol es obligatorio.";

            if (rol.Nombre.Length > 50)
                return "El nombre del rol no puede superar los 50 caracteres.";

            // Descripcion: opcional, pero con limite
            if (!string.IsNullOrWhiteSpace(rol.Descripcion) && rol.Descripcion.Length > 200)
                return "La descripción no puede superar los 200 caracteres.";

            return "";
        }
    }
}
