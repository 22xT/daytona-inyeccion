using System.Data;
using System.Data.SqlClient;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class EstadoVentaController : ApiController
    {
        // GET: api/EstadoVenta  (todos los roles autenticados, lo necesitan dropdowns)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema")]
        public DataTable Get()
        {
            EstadoVenta oEstado = new EstadoVenta();
            return oEstado.ListarTodos();
        }

        // GET: api/EstadoVenta/5  (todos los roles autenticados)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema")]
        public DataTable Get(int id)
        {
            EstadoVenta oEstado = new EstadoVenta();
            oEstado.Id = id;
            return oEstado.ListarPorId();
        }

        // POST: api/EstadoVenta  (solo Administrador)
        [AuthorizeJwt(Roles = "Administrador")]
        public IHttpActionResult Post([FromBody] EstadoVenta estado)
        {
            string error = Validar(estado);
            if (error != "")
                return BadRequest(error);

            try
            {
                estado.Guardar();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe un estado con ese nombre.");

                return BadRequest("No se pudo guardar el estado. " + ex.Message);
            }

            return Ok();
        }

        // PUT: api/EstadoVenta/5  (solo Administrador)
        [AuthorizeJwt(Roles = "Administrador")]
        public IHttpActionResult Put(int id, [FromBody] EstadoVenta estado)
        {
            // Proteger los estados del sistema (Confirmada=1, Anulada=2)
            if (id == 1 || id == 2)
                return BadRequest("Los estados Confirmada y Anulada son del sistema y no pueden modificarse.");

            string error = Validar(estado);
            if (error != "")
                return BadRequest(error);

            estado.Id = id;

            try
            {
                estado.Editar();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe un estado con ese nombre.");

                return BadRequest("No se pudo editar el estado. " + ex.Message);
            }

            return Ok();
        }

        // DELETE: api/EstadoVenta/5  (solo Administrador)
        [AuthorizeJwt(Roles = "Administrador")]
        public IHttpActionResult Delete(int id)
        {
            EstadoVenta oEstado = new EstadoVenta();
            oEstado.Id = id;

            try
            {
                oEstado.Eliminar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo dar de baja el estado. " + ex.Message);
            }

            return Ok();
        }

        // PUT: api/EstadoVenta/5/Activar  (solo Administrador)
        [HttpPut]
        [Route("api/EstadoVenta/{id:int}/Activar")]
        [AuthorizeJwt(Roles = "Administrador")]
        public IHttpActionResult Activar(int id)
        {
            EstadoVenta oEstado = new EstadoVenta();
            oEstado.Id = id;

            try
            {
                oEstado.Activar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo reactivar el estado. " + ex.Message);
            }

            return Ok();
        }

        private string Validar(EstadoVenta estado)
        {
            if (estado == null)
                return "No se recibieron datos del estado.";

            if (string.IsNullOrWhiteSpace(estado.Nombre))
                return "El nombre del estado es obligatorio.";

            if (estado.Nombre.Length > 50)
                return "El nombre del estado no puede superar los 50 caracteres.";

            return "";
        }
    }
}