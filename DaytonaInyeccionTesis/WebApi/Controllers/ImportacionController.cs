using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    /* Listas de precios de proveedores: cargar, comparar e importar.
       Los precios de venta no se tocan aca: se aplican uno por uno con
       api/Repuesto/{id}/AplicarPrecio, solo los que la persona marca. */
    [AuthorizeJwt(Roles = "Dueño,Administrador")]
    public class ImportacionController : ApiController
    {
        public class FilasDto
        {
            public bool PrimeraTanda { get; set; }
            public List<List<string>> Filas { get; set; }
        }
        public class ProcesarDto { public DateTime? FechaLista { get; set; } }

        // GET api/Importacion/Perfiles — proveedores que se pueden actualizar
        [HttpGet, Route("api/Importacion/Perfiles")]
        public DataTable Perfiles()
        {
            return new Importacion().Perfiles();
        }

        // POST api/Importacion/Filas — una tanda de filas del Excel
        [HttpPost, Route("api/Importacion/Filas")]
        public IHttpActionResult Filas([FromBody] FilasDto d)
        {
            if (d == null || d.Filas == null || d.Filas.Count == 0) return BadRequest("No llegaron filas.");
            if (d.Filas.Count > 10000) return BadRequest("Mandá las filas en tandas de hasta 10.000.");
            try
            {
                int total = new Importacion().CargarFilas(d.Filas, d.PrimeraTanda);
                return Ok(new { FilasCargadas = total });
            }
            catch (SqlException ex) { return BadRequest("No se pudieron cargar las filas. " + ex.Message); }
        }

        // GET api/Importacion/5/Comparar — que cambia, sin escribir nada
        [HttpGet, Route("api/Importacion/{idProveedor:int}/Comparar")]
        public IHttpActionResult Comparar(int idProveedor)
        {
            try
            {
                DataSet ds = new Importacion().Comparar(idProveedor);
                return Ok(new
                {
                    Resumen = ds.Tables.Count > 0 ? ds.Tables[0] : null,
                    PorRubro = ds.Tables.Count > 1 ? ds.Tables[1] : null,
                    Raros = ds.Tables.Count > 2 ? ds.Tables[2] : null,
                    TusRepuestos = ds.Tables.Count > 3 ? ds.Tables[3] : null
                });
            }
            catch (SqlException ex)
            {
                if (ex.Number >= 50000) return BadRequest(ex.Message);
                return BadRequest("No se pudo comparar la lista. " + ex.Message);
            }
        }

        // POST api/Importacion/5/Procesar — importar de verdad
        [HttpPost, Route("api/Importacion/{idProveedor:int}/Procesar")]
        public IHttpActionResult Procesar(int idProveedor, [FromBody] ProcesarDto d)
        {
            DateTime fecha = (d != null && d.FechaLista.HasValue) ? d.FechaLista.Value : DateTime.Today;
            try
            {
                DataSet ds = new Importacion().Procesar(idProveedor, fecha);
                return Ok(new { Resultado = ds.Tables.Count > 0 ? ds.Tables[ds.Tables.Count - 1] : null });
            }
            catch (SqlException ex)
            {
                if (ex.Number >= 50000) return BadRequest(ex.Message);
                return BadRequest("No se pudo importar la lista. " + ex.Message);
            }
        }
    }
}
