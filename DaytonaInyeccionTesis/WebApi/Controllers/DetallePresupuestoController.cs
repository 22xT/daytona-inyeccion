using System.Data.SqlClient;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class DetallePresupuestoController : ApiController
    {
        // POST: api/DetallePresupuesto
        // Se llama una vez por cada renglon, igual que DetallePedido.
        [AuthorizeJwt(Roles = "Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Post([FromBody] DetallePresupuesto detalle)
        {
            string error = ValidarDetalle(detalle);
            if (error != "")
                return BadRequest(error);

            try
            {
                detalle.Guardar();
                return Ok();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 547)
                    return BadRequest("El presupuesto o el repuesto indicado no existe.");

                return BadRequest("No se pudo agregar el renglon al presupuesto. " + ex.Message);
            }
        }

        private string ValidarDetalle(DetallePresupuesto detalle)
        {
            if (detalle == null)
                return "No se recibieron datos del renglon.";

            if (detalle.IdPresupuesto <= 0)
                return "Debe indicar el presupuesto al que pertenece el renglon.";

            if (detalle.IdRepuesto <= 0)
                return "Debe seleccionar un repuesto.";

            if (detalle.Cantidad <= 0)
                return "La cantidad debe ser mayor a cero.";

            if (detalle.Cantidad > 9999)
                return "La cantidad es demasiado alta.";

            if (detalle.PrecioUnitario < 0)
                return "El precio no puede ser negativo.";

            if (detalle.PrecioUnitario > 10000000)
                return "El precio no puede superar los $10.000.000.";

            return "";
        }
    }
}
