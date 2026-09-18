using System.Data;
using System.Data.SqlClient;
using System.Security.Claims;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class PedidoController : ApiController
    {
        // GET: api/Pedido  (todos los roles autenticados menos Analista y Sistema)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataTable Get()
        {
            Pedido oPedido = new Pedido();
            return oPedido.ListarTodos();
        }

        // GET: api/Pedido/5  (mismo criterio)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataSet Get(int id)
        {
            Pedido oPedido = new Pedido();
            oPedido.Id = id;
            return oPedido.ListarPorId();
        }

        // POST: api/Pedido  (los que pueden crear pedidos)
        [AuthorizeJwt(Roles = "Administrador,Supervisor,Vendedor,Sistema")]
        public IHttpActionResult Post([FromBody] Pedido pedido)
        {
            string error = ValidarPedido(pedido);
            if (error != "")
                return BadRequest(error);

            try
            {
                int idPedido = pedido.Guardar();
                return Ok(idPedido);
            }
            catch (SqlException ex)
            {
                if (ex.Number == 547)
                    return BadRequest("El proveedor indicado no existe.");

                return BadRequest("No se pudo guardar el pedido. " + ex.Message);
            }
        }

        // PUT: api/Pedido/5  (cambio de estado: recibir o cancelar)
        [AuthorizeJwt(Roles = "Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Put(int id, [FromBody] Pedido pedido)
        {
            if (id <= 0)
                return BadRequest("El identificador del pedido no es válido.");

            if (pedido == null)
                return BadRequest("No se recibieron datos del pedido.");

            if (pedido.IdEstado <= 0)
                return BadRequest("Debe indicar el estado al que pasa el pedido.");

            int idUsuario = ObtenerIdUsuarioActual();
            pedido.Id = id;

            try
            {
                // Si esta cancelando (estado 3), pasamos el usuario para auditoria
                pedido.Editar(idUsuario);
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo actualizar el pedido. " + ex.Message);
            }

            return Ok();
        }

        // DELETE: api/Pedido/5  (solo Administrador, por si hace falta borrar fisicamente)
        [AuthorizeJwt(Roles = "Administrador")]
        public IHttpActionResult Delete(int id)
        {
            if (id <= 0)
                return BadRequest("El identificador del pedido no es válido.");

            Pedido oPedido = new Pedido();
            oPedido.Id = id;

            try
            {
                oPedido.Eliminar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo eliminar el pedido. " + ex.Message);
            }

            return Ok();
        }

        // Valida el pedido y que el proveedor exista y este activo
        private string ValidarPedido(Pedido pedido)
        {
            if (pedido == null)
                return "No se recibieron datos del pedido.";

            if (pedido.IdProveedor <= 0)
                return "Debe seleccionar un proveedor para el pedido.";

            if (pedido.Total <= 0)
                return "El total del pedido debe ser mayor a cero.";

            if (pedido.Total > 999999999)
                return "El total del pedido es demasiado alto.";

            // No alcanza con que haya llegado un Id: verificamos que exista y este activo
            Proveedor oProveedor = new Proveedor();
            oProveedor.Id = pedido.IdProveedor;
            DataTable dt = oProveedor.ListarPorId();

            if (dt == null || dt.Rows.Count == 0)
                return "El proveedor seleccionado no existe.";

            bool activo = System.Convert.ToBoolean(dt.Rows[0]["Activo"]);
            if (!activo)
                return "El proveedor seleccionado está dado de baja. Reactivalo o elegí otro.";

            return "";
        }

        private int ObtenerIdUsuarioActual()
        {
            var identity = User.Identity as ClaimsIdentity;
            if (identity == null) return 0;

            var claim = identity.FindFirst(ClaimTypes.NameIdentifier)
                     ?? identity.FindFirst("sub")
                     ?? identity.FindFirst("Sub");

            int id;
            if (claim != null && int.TryParse(claim.Value, out id))
                return id;
            return 0;
        }
    }
}