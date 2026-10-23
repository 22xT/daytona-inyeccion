using System.Data;
using System.Data.SqlClient;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class ProveedorRepuestoController : ApiController
    {
        /* GET: api/ProveedorRepuesto
           Es el que consume PedidoNuevo.html para comparar precios en
           Reposicion sugerida. Devuelve SOLO los articulos enlazados a
           un repuesto del catalogo propio: la lista completa son 53.188
           filas y el 99% no forma parte del catalogo. */
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista")]
        public DataTable Get()
        {
            ProveedorRepuesto oPR = new ProveedorRepuesto();
            return oPR.ListarEnlazados();
        }

        // GET: api/ProveedorRepuesto/Buscar?idProveedor=3&texto=abrazadera
        // Para incorporar articulos de la lista al catalogo propio.
        [HttpGet]
        [Route("api/ProveedorRepuesto/Buscar")]
        [AuthorizeJwt(Roles = "Administrador,Supervisor,Analista")]
        public DataTable Buscar(int idProveedor = 0, string texto = null,
                                bool soloSinEnlazar = true, int tope = 100)
        {
            ProveedorRepuesto oPR = new ProveedorRepuesto();
            return oPR.Buscar(idProveedor, texto, soloSinEnlazar, tope);
        }

        // GET: api/ProveedorRepuesto/Sugerencias?idProveedor=3
        // Candidatos a enlazar, con nivel de confianza. No enlaza nada.
        [HttpGet]
        [Route("api/ProveedorRepuesto/Sugerencias")]
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public DataTable Sugerencias(int idProveedor)
        {
            ProveedorRepuesto oPR = new ProveedorRepuesto();
            return oPR.SugerirEnlaces(idProveedor);
        }

        // PUT: api/ProveedorRepuesto/5/Desvincular
        // Deshace un enlace hecho por error. Tu repuesto no cambia.
        [HttpPut]
        [Route("api/ProveedorRepuesto/{id:int}/Desvincular")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public IHttpActionResult Desvincular(int id)
        {
            ProveedorRepuesto oPR = new ProveedorRepuesto();
            oPR.Id = id;
            try
            {
                oPR.Desvincular();
                return Ok();
            }
            catch (SqlException ex)
            {
                if (ex.Number >= 50000) return BadRequest(ex.Message);
                return BadRequest("No se pudo desvincular el artículo.");
            }
        }

        // PUT: api/ProveedorRepuesto/5/Enlazar
        // Confirma el enlace. Se hace de a uno y con intervencion humana:
        // un enlace erroneo fusiona repuestos distintos y corrompe el stock.
        [HttpPut]
        [Route("api/ProveedorRepuesto/{id:int}/Enlazar")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public IHttpActionResult Enlazar(int id, [FromBody] ProveedorRepuesto datos)
        {
            if (datos == null || !datos.IdRepuesto.HasValue || datos.IdRepuesto.Value <= 0)
                return BadRequest("Debe indicarse el repuesto con el que se enlaza.");

            ProveedorRepuesto oPR = new ProveedorRepuesto();
            oPR.Id = id;
            oPR.IdRepuesto = datos.IdRepuesto;

            try
            {
                oPR.Enlazar();
                return Ok();
            }
            catch (SqlException ex)
            {
                if (ex.Number >= 50000) return BadRequest(ex.Message);
                return BadRequest("No se pudo enlazar el artículo.");
            }
        }
    }
}
