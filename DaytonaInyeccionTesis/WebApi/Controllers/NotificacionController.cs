using System.Data;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt(Roles = "Dueño,Administrador")]
    public class NotificacionController : ApiController
    {
        // GET: api/Notificacion/Resumen
        // Devuelve un objeto consolidado con todos los eventos relevantes
        [HttpGet]
        [Route("api/Notificacion/Resumen")]
        public IHttpActionResult GetResumen()
        {
            Notificacion oNot = new Notificacion();
            DataTable ventas = oNot.VentasAnuladasRecientes();
            DataTable pedidos = oNot.PedidosCanceladosRecientes();
            DataTable ajustes = oNot.AjustesStockRecientes();
            int solicitudes = oNot.SolicitudesResetPendientes();
            int stockCritico = oNot.RepuestosStockCritico();
            int total = ventas.Rows.Count + pedidos.Rows.Count + ajustes.Rows.Count
                        + solicitudes + (stockCritico > 0 ? 1 : 0);
            return Ok(new
            {
                VentasAnuladas = ventas,
                PedidosCancelados = pedidos,
                AjustesStock = ajustes,
                SolicitudesReset = solicitudes,
                StockCritico = stockCritico,
                Total = total
            });
        }
    }
}