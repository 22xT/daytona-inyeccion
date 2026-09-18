using System.Data;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class StockController : ApiController
    {
        // GET: api/Stock  (todos los roles autenticados)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema")]
        public DataTable Get()
        {
            Stock oStock = new Stock();
            return oStock.ListarTodos();
        }

        // GET: api/Stock/5  (stock de un repuesto)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema")]
        public DataTable Get(int id)
        {
            Stock oStock = new Stock();
            oStock.IdRepuesto = id;
            return oStock.ListarPorRepuesto();
        }
    }
}