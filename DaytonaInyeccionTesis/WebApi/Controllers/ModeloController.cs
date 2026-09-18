using System.Data;
using System.Data.SqlClient;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class ModeloController : ApiController
    {
        // GET: api/Modelo  (todos los roles autenticados)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema")]
        public DataTable Get()
        {
            Modelo oModelo = new Modelo();
            return oModelo.ListarTodos();
        }

        // GET: api/Modelo/5  -> modelos de una marca (compatibilidad con codigo existente)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema")]
        public DataTable Get(int id)
        {
            Modelo oModelo = new Modelo();
            oModelo.IdMarca = id;
            return oModelo.ListarPorMarca();
        }

        // GET: api/Modelo/Uno/5  -> trae un modelo individual por Id
        [HttpGet]
        [Route("api/Modelo/Uno/{id:int}")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema")]
        public DataTable GetUno(int id)
        {
            Modelo oModelo = new Modelo();
            oModelo.Id = id;
            return oModelo.ListarPorId();
        }

        // POST: api/Modelo  (Administrador y Analista)
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult Post([FromBody] Modelo modelo)
        {
            string error = ValidarModelo(modelo);
            if (error != "")
                return BadRequest(error);

            try
            {
                modelo.Guardar();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe un modelo con ese nombre para esa marca.");

                return BadRequest("No se pudo guardar el modelo. " + ex.Message);
            }

            return Ok();
        }

        // PUT: api/Modelo/5  (Administrador y Analista)
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult Put(int id, [FromBody] Modelo modelo)
        {
            string error = ValidarModelo(modelo);
            if (error != "")
                return BadRequest(error);

            modelo.Id = id;

            try
            {
                modelo.Editar();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe un modelo con ese nombre para esa marca.");

                return BadRequest("No se pudo editar el modelo. " + ex.Message);
            }

            return Ok();
        }

        // DELETE: api/Modelo/5  (Administrador y Analista)
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult Delete(int id)
        {
            Modelo oModelo = new Modelo();
            oModelo.Id = id;

            try
            {
                oModelo.Eliminar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo dar de baja el modelo. " + ex.Message);
            }

            return Ok();
        }

        // PUT: api/Modelo/5/Activar  (Administrador y Analista)
        [HttpPut]
        [Route("api/Modelo/{id:int}/Activar")]
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult Activar(int id)
        {
            Modelo oModelo = new Modelo();
            oModelo.Id = id;

            try
            {
                oModelo.Activar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo reactivar el modelo. " + ex.Message);
            }

            return Ok();
        }

        private string ValidarModelo(Modelo modelo)
        {
            if (modelo == null)
                return "No se recibieron datos del modelo.";

            if (string.IsNullOrWhiteSpace(modelo.Nombre))
                return "El nombre del modelo es obligatorio.";

            if (modelo.Nombre.Length > 100)
                return "El nombre del modelo no puede superar los 100 caracteres.";

            if (modelo.IdMarca <= 0)
                return "Tenés que seleccionar una marca.";

            return "";
        }
    }
}