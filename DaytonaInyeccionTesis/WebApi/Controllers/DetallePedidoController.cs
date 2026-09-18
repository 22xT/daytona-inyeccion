using System.Data;
using System.Data.SqlClient;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class DetallePedidoController : ApiController
    {
        private const int CANTIDAD_MAXIMA = 500;

        // GET: api/DetallePedido/5
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataTable Get(int idPedido)
        {
            return new DetallePedido { IdPedido = idPedido }.ListarPorPedido();
        }

        // POST: api/DetallePedido
        [AuthorizeJwt(Roles = "Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Post([FromBody] DetallePedido detalle)
        {
            string error = Validar(detalle);
            if (error != "")
                return BadRequest(error);

            try
            {
                detalle.Guardar();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 547)
                    return BadRequest("El pedido o el repuesto indicado no existe.");

                return BadRequest("No se pudo agregar el ítem al pedido. " + ex.Message);
            }

            return Ok();
        }

        // DELETE: api/DetallePedido/5
        [AuthorizeJwt(Roles = "Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Delete(int id)
        {
            if (id <= 0)
                return BadRequest("El identificador del ítem no es válido.");

            try
            {
                new DetallePedido { Id = id }.Eliminar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo quitar el ítem del pedido. " + ex.Message);
            }

            return Ok();
        }

        private string Validar(DetallePedido d)
        {
            if (d == null)
                return "No se recibieron datos del ítem.";

            if (d.IdPedido <= 0)
                return "El pedido indicado no es válido.";

            if (d.IdRepuesto <= 0)
                return "Debe indicar un repuesto válido.";

            if (d.Cantidad <= 0)
                return "La cantidad debe ser mayor a cero.";

            if (d.Cantidad > CANTIDAD_MAXIMA)
                return "La cantidad no puede superar las " + CANTIDAD_MAXIMA + " unidades por ítem.";

            if (d.PrecioUnitario <= 0)
                return "El precio unitario debe ser mayor a cero.";

            if (d.PrecioUnitario > 50000000)
                return "El precio unitario ingresado es demasiado alto. Verificá el monto.";

            return "";
        }
    }
}