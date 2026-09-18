using System;
using System.Data;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class ReporteController : ApiController
    {
        // GET: api/Reporte/StockCritico
        [HttpGet]
        [Route("api/Reporte/StockCritico")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista")]
        public DataTable StockCritico()
        {
            ReporteStockCritico rep = new ReporteStockCritico();
            return rep.Obtener();
        }

        // GET: api/Reporte/VentasResumen?desde=2026-01-01&hasta=2026-12-31
        [HttpGet]
        [Route("api/Reporte/VentasResumen")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public DataTable VentasResumen(DateTime desde, DateTime hasta)
        {
            ReporteVentas rep = new ReporteVentas();
            return rep.Resumen(desde, hasta);
        }

        // GET: api/Reporte/VentasPorDia?desde=2026-01-01&hasta=2026-12-31
        [HttpGet]
        [Route("api/Reporte/VentasPorDia")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public DataTable VentasPorDia(DateTime desde, DateTime hasta)
        {
            ReporteVentas rep = new ReporteVentas();
            return rep.PorDia(desde, hasta);
        }

        // GET: api/Reporte/CajaResumen?desde=2026-01-01&hasta=2026-12-31
        [HttpGet]
        [Route("api/Reporte/CajaResumen")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public DataTable CajaResumen(DateTime desde, DateTime hasta)
        {
            ReporteCaja rep = new ReporteCaja();
            return rep.Resumen(desde, hasta);
        }

        // GET: api/Reporte/CajaPorConcepto?desde=2026-01-01&hasta=2026-12-31
        [HttpGet]
        [Route("api/Reporte/CajaPorConcepto")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public DataTable CajaPorConcepto(DateTime desde, DateTime hasta)
        {
            ReporteCaja rep = new ReporteCaja();
            return rep.PorConcepto(desde, hasta);
        }
        // GET: api/Reporte/Dashboard?desde=2026-01-01&hasta=2026-12-31
        [HttpGet]
        [Route("api/Reporte/Dashboard")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public DataSet Dashboard(DateTime desde, DateTime hasta)
        {
            Dashboard dash = new Dashboard();
            return dash.Obtener(desde, hasta);
        }
    }
}