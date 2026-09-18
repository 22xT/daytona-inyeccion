using System.Data;
using System.Data.SqlClient;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class IndicadorController : ApiController
    {
        /* GET: api/Indicador
           Contadores que se muestran como globo en la barra superior.
           Se ejecuta en cada carga de pantalla, asi que la consulta
           tiene que ser liviana. */
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista")]
        public DataTable Get()
        {
            Indicador oIndicador = new Indicador();
            return oIndicador.Resumen();
        }
    }
}
