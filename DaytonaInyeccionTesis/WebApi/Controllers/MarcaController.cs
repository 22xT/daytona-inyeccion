using System.Data;
using System.Data.SqlClient;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class MarcaController : ApiController
    {
        // GET: api/Marca  (todos los roles autenticados)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema")]
        public DataTable Get()
        {
            Marca oMarca = new Marca();
            return oMarca.ListarTodos();
        }

        // GET: api/Marca/5  (todos los roles autenticados)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema")]
        public DataTable Get(int id)
        {
            Marca oMarca = new Marca();
            oMarca.Id = id;
            return oMarca.ListarPorId();
        }

        // POST: api/Marca  (Administrador y Analista)
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult Post([FromBody] Marca marca)
        {
            string error = ValidarMarca(marca);
            if (error != "")
                return BadRequest(error);

            try
            {
                marca.Guardar();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe una marca con ese nombre.");

                return BadRequest("No se pudo guardar la marca. " + ex.Message);
            }

            return Ok();
        }

        // PUT: api/Marca/5  (Administrador y Analista)
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult Put(int id, [FromBody] Marca marca)
        {
            string error = ValidarMarca(marca);
            if (error != "")
                return BadRequest(error);

            marca.Id = id;

            try
            {
                marca.Editar();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe una marca con ese nombre.");

                return BadRequest("No se pudo editar la marca. " + ex.Message);
            }

            return Ok();
        }

        // DELETE: api/Marca/5  (Administrador y Analista)
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult Delete(int id)
        {
            Marca oMarca = new Marca();
            oMarca.Id = id;

            try
            {
                oMarca.Eliminar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo dar de baja la marca. " + ex.Message);
            }

            return Ok();
        }

        // PUT: api/Marca/5/Activar  (Administrador y Analista)
        [HttpPut]
        [Route("api/Marca/{id:int}/Activar")]
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult Activar(int id)
        {
            Marca oMarca = new Marca();
            oMarca.Id = id;

            try
            {
                oMarca.Activar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo reactivar la marca. " + ex.Message);
            }

            return Ok();
        }

        private string ValidarMarca(Marca marca)
        {
            if (marca == null)
                return "No se recibieron datos de la marca.";

            if (string.IsNullOrWhiteSpace(marca.Nombre))
                return "El nombre de la marca es obligatorio.";

            if (marca.Nombre.Length > 100)
                return "El nombre de la marca no puede superar los 100 caracteres.";

            return "";
        }
    }
}