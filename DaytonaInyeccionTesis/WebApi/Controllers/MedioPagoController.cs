using System;
using System.Data;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class MedioPagoController : ApiController
    {
        // GET: api/MedioPago — para los botones de la pantalla de venta
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista")]
        public DataTable Get()
        {
            return new MedioPago().Listar();
        }

        // GET: api/MedioPago/Venta/5 — como se pago una venta
        [HttpGet]
        [Route("api/MedioPago/Venta/{idVenta:int}")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista")]
        public DataTable PagosDeVenta(int idVenta)
        {
            return new MedioPago().PagosDeVenta(idVenta);
        }

        // GET: api/MedioPago/Cuentas?desde&hasta — saldo de banco y MP
        [HttpGet]
        [Route("api/MedioPago/Cuentas")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Analista")]
        public DataTable Cuentas(DateTime? desde = null, DateTime? hasta = null)
        {
            return new MedioPago().ResumenCuentas(desde, hasta);
        }

        // GET: api/MedioPago/Resumen?desde&hasta — cobrado por medio
        [HttpGet]
        [Route("api/MedioPago/Resumen")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public DataTable Resumen(DateTime? desde = null, DateTime? hasta = null)
        {
            return new MedioPago().PorMedio(desde, hasta);
        }
    }
}
