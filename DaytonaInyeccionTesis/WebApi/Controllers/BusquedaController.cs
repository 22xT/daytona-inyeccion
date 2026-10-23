using System;
using System.Data;
using System.Data.SqlClient;
using System.Security.Claims;
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
                           bool soloConStock = false, int tope = 60, string origen = "BUSCADOR")
        {
            Busqueda oBusqueda = new Busqueda();
            DataSet ds = oBusqueda.Universal(texto, idProveedor, soloConStock, tope);

            // Registro de busquedas (script 78). Solo la busqueda completa,
            // sin filtro de proveedor; si falla, la busqueda sigue igual.
            if (idProveedor <= 0 && !soloConStock)
            {
                try { oBusqueda.Registrar(ObtenerIdUsuarioActual(), texto, origen, ds); }
                catch (Exception) { }
            }
            return ds;
        }

        public class RegistroDto { public string Texto { get; set; } public string Origen { get; set; } }

        // POST: api/Busqueda/Registro — para pantallas que filtran en el
        // navegador (la venta): la API busca igual que el Buscador y lo anota.
        [HttpPost]
        [Route("api/Busqueda/Registro")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista")]
        public IHttpActionResult Registro([FromBody] RegistroDto d)
        {
            if (d == null || string.IsNullOrWhiteSpace(d.Texto) || d.Texto.Trim().Length < 3) return Ok();
            try
            {
                Busqueda b = new Busqueda();
                DataSet ds = b.Universal(d.Texto.Trim(), 0, false, 60);
                b.Registrar(ObtenerIdUsuarioActual(), d.Texto.Trim(), string.IsNullOrEmpty(d.Origen) ? "VENTA" : d.Origen, ds);
            }
            catch (Exception) { }
            return Ok();
        }

        // GET: api/Busqueda/Reporte?dias=30
        // Lo que se busca, lo que no tenemos y cuanto termina en venta.
        [HttpGet]
        [Route("api/Busqueda/Reporte")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public IHttpActionResult Reporte(int dias = 30)
        {
            try
            {
                DataSet ds = new Busqueda().Reporte(dias);
                Func<int, DataTable> t = i => ds.Tables.Count > i ? ds.Tables[i] : null;
                return Ok(new { Resumen = t(0), NoTenemos = t(1), MasBuscados = t(2), SinResultados = t(3), PorDia = t(4) });
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo armar el reporte de búsquedas. " + ex.Message);
            }
        }

        private int ObtenerIdUsuarioActual()
        {
            var identity = User.Identity as ClaimsIdentity;
            if (identity == null) return 0;
            var claim = identity.FindFirst(ClaimTypes.NameIdentifier) ?? identity.FindFirst("sub") ?? identity.FindFirst("Sub");
            int id;
            return (claim != null && int.TryParse(claim.Value, out id)) ? id : 0;
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
