using System;
using System.Data;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class AnalisisController : ApiController
    {
        /* GET: api/Analisis/Pronostico?mesesHistoria=6&mesesProyectar=3
           Serie mensual historica + proyeccion por regresion lineal.
           Devuelve R2 para que la pantalla avise si la proyeccion es debil. */
        [HttpGet]
        [Route("api/Analisis/Pronostico")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Analista")]
        public DataTable Pronostico(int mesesHistoria = 6, int mesesProyectar = 3)
        {
            Analisis o = new Analisis();
            return o.Pronostico(mesesHistoria, mesesProyectar);
        }

        /* GET: api/Analisis/PuntoEquilibrio?desde=2026-09-01&hasta=2026-09-30
           Sin fechas: el mes actual. Requiere CostosFijosMensuales cargado. */
        [HttpGet]
        [Route("api/Analisis/PuntoEquilibrio")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Analista")]
        public DataTable PuntoEquilibrio(DateTime? desde = null, DateTime? hasta = null)
        {
            Analisis o = new Analisis();
            return o.PuntoEquilibrio(desde, hasta);
        }

        /* GET: api/Analisis/MapaCalor?desde=...&hasta=...
           Operaciones por dia de la semana y hora. Sin fechas: ultimas 8 semanas. */
        [HttpGet]
        [Route("api/Analisis/MapaCalor")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public DataTable MapaCalor(DateTime? desde = null, DateTime? hasta = null)
        {
            Analisis o = new Analisis();
            return o.MapaCalor(desde, hasta);
        }

        /* GET: api/Analisis/Periodo?desde=...&hasta=...
           Indicadores del periodo comparados con el anterior de igual duracion. */
        [HttpGet]
        [Route("api/Analisis/Periodo")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public DataTable Periodo(DateTime? desde = null, DateTime? hasta = null)
        {
            Analisis o = new Analisis();
            return o.Periodo(desde, hasta);
        }
    }
}
