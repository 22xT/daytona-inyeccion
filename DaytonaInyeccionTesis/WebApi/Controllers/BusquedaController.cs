using System.Data;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class BusquedaController : ApiController
    {
        /* GET: api/Busqueda?texto=bomba agua suran

           Devuelve un DataSet con dos tablas. El frontend recibe
           [ [propios], [proveedores] ] y las muestra separadas. */
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista")]
        public DataSet Get(string texto, int idProveedor = 0,
                           bool soloConStock = false, int tope = 60)
        {
            Busqueda oBusqueda = new Busqueda();
            return oBusqueda.Universal(texto, idProveedor, soloConStock, tope);
        }

        // GET: api/Busqueda/Oportunidades?diferenciaMinima=5
        // Repuestos del catalogo disponibles mas baratos en otro proveedor.
        [HttpGet]
        [Route("api/Busqueda/Oportunidades")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public DataTable Oportunidades(decimal diferenciaMinima = 5)
        {
            Busqueda oBusqueda = new Busqueda();
            return oBusqueda.Oportunidades(diferenciaMinima);
        }

        // GET: api/Busqueda/Cobertura?dias=120
        // Que parte de lo que se vende tiene proveedor vinculado.
        [HttpGet]
        [Route("api/Busqueda/Cobertura")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Analista")]
        public DataTable Cobertura(int dias = 120)
        {
            Busqueda oBusqueda = new Busqueda();
            return oBusqueda.Cobertura(dias);
        }
    }
}
