using System.Data;
using System.Data.SqlClient;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class RubroController : ApiController
    {
        // GET: api/Rubro  (todos los roles autenticados)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema")]
        public DataTable Get()
        {
            Rubro oRubro = new Rubro();
            return oRubro.ListarTodos();
        }

        // GET: api/Rubro/5  (todos los roles autenticados)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema")]
        public DataTable Get(int id)
        {
            Rubro oRubro = new Rubro();
            oRubro.Id = id;
            return oRubro.ListarPorId();
        }

        // POST: api/Rubro  (Administrador y Analista)
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult Post([FromBody] Rubro rubro)
        {
            string error = ValidarRubro(rubro);
            if (error != "")
                return BadRequest(error);

            try
            {
                rubro.Guardar();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe un rubro con ese nombre o sigla.");

                return BadRequest("No se pudo guardar el rubro. " + ex.Message);
            }

            return Ok();
        }

        // PUT: api/Rubro/5  (Administrador y Analista)
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult Put(int id, [FromBody] Rubro rubro)
        {
            string error = ValidarRubro(rubro);
            if (error != "")
                return BadRequest(error);

            rubro.Id = id;

            try
            {
                rubro.Editar();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe un rubro con ese nombre o sigla.");

                return BadRequest("No se pudo editar el rubro. " + ex.Message);
            }

            return Ok();
        }

        // DELETE: api/Rubro/5  (Administrador y Analista)
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult Delete(int id)
        {
            Rubro oRubro = new Rubro();
            oRubro.Id = id;

            try
            {
                oRubro.Eliminar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo dar de baja el rubro. " + ex.Message);
            }

            return Ok();
        }

        // PUT: api/Rubro/5/Activar  (Administrador y Analista)
        [HttpPut]
        [Route("api/Rubro/{id:int}/Activar")]
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult Activar(int id)
        {
            Rubro oRubro = new Rubro();
            oRubro.Id = id;

            try
            {
                oRubro.Activar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo reactivar el rubro. " + ex.Message);
            }

            return Ok();
        }

        private string ValidarRubro(Rubro rubro)
        {
            if (rubro == null)
                return "No se recibieron datos del rubro.";

            if (string.IsNullOrWhiteSpace(rubro.Nombre))
                return "El nombre del rubro es obligatorio.";

            if (rubro.Nombre.Length > 100)
                return "El nombre del rubro no puede superar los 100 caracteres.";

            if (string.IsNullOrWhiteSpace(rubro.Sigla))
                return "La sigla del rubro es obligatoria.";

            if (rubro.Sigla.Length > 5)
                return "La sigla no puede superar los 5 caracteres.";

            return "";
        }
    }
}