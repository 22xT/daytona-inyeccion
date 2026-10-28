using System;
using System.Data;
using System.Data.SqlClient;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    /* Libro IVA ventas y compras (script 96) */
    [AuthorizeJwt]
    public class LibroIvaController : ApiController
    {
        // GET api/LibroIva?desde=&hasta=&pruebas=false
        [HttpGet, Route("api/LibroIva")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Analista")]
        public IHttpActionResult Obtener(DateTime desde, DateTime hasta, bool pruebas = false)
        {
            if (desde.Date > hasta.Date) return BadRequest("La fecha desde no puede ser posterior a la fecha hasta.");
            if ((hasta - desde).TotalDays > 400) return BadRequest("Elegí un período de hasta un año.");
            try
            {
                var libro = new LibroIva();
                DataSet v = libro.Ventas(desde, hasta, pruebas);
                DataSet c = libro.Compras(desde, hasta);
                DataSet f = libro.Faltantes(desde, hasta, pruebas);
                return Ok(new
                {
                    Ventas = v.Tables[0], VentasIva = v.Tables[1],
                    Compras = c.Tables[0], ComprasIva = c.Tables[1],
                    VentasSinAutorizar = f.Tables[0], ComprasSinDatos = f.Tables[1]
                });
            }
            catch (SqlException ex)
            {
                return BadRequest(ex.Number >= 50000 ? ex.Message : "No se pudo armar el libro. Intentalo de nuevo o avisá a sistemas.");
            }
        }

        // GET api/LibroIva/Archivo?archivo=ventas-cbte&desde=&hasta= — para importar en Libro IVA Digital
        [HttpGet, Route("api/LibroIva/Archivo")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Analista")]
        public IHttpActionResult Archivo(string archivo, DateTime desde, DateTime hasta)
        {
            if (archivo != "ventas-cbte" && archivo != "ventas-alicuotas" && archivo != "compras-cbte" && archivo != "compras-alicuotas")
                return BadRequest("Archivo no válido.");
            if (desde.Date > hasta.Date) return BadRequest("La fecha desde no puede ser posterior a la fecha hasta.");
            byte[] datos;
            try { datos = new LibroIva().Archivo(archivo, desde, hasta); }
            catch (SqlException) { return BadRequest("No se pudo armar el archivo. Intentalo de nuevo o avisá a sistemas."); }
            catch (InvalidOperationException ex) { return BadRequest("El archivo salió con un formato inválido: " + ex.Message); }

            string nombre = "LIBRO_IVA_DIGITAL_" + archivo.ToUpper().Replace("-", "_") + "_" + desde.ToString("yyyyMM") + ".txt";
            var resp = new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(datos) };
            resp.Content.Headers.ContentType = new MediaTypeHeaderValue("text/plain") { CharSet = "windows-1252" };
            resp.Content.Headers.ContentDisposition = new ContentDispositionHeaderValue("attachment") { FileName = nombre };
            return ResponseMessage(resp);
        }
    }
}
