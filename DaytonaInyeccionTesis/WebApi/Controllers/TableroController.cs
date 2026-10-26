using System;
using System.Data;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    /* Tablero de decisiones (script 81).
       Sin fechas: el mes en curso (resumen) o los ultimos 12 meses (areas). */
    [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
    public class TableroController : ApiController
    {
        private static void Rango(ref DateTime? desde, ref DateTime? hasta, int mesesPorDefecto)
        {
            DateTime hoy = DateTime.Today;
            if (!hasta.HasValue) hasta = hoy;
            if (!desde.HasValue) desde = new DateTime(hasta.Value.Year, hasta.Value.Month, 1).AddMonths(-(mesesPorDefecto - 1));
            if (hasta.Value < desde.Value) hasta = desde;
        }

        // GET api/Tablero/Resumen?desde=2026-10-01&hasta=2026-10-25
        [HttpGet, Route("api/Tablero/Resumen")]
        public DataSet Resumen(DateTime? desde = null, DateTime? hasta = null)
        {
            Rango(ref desde, ref hasta, 1);
            return new Tablero().Resumen(desde, hasta);
        }

        [HttpGet, Route("api/Tablero/Ventas")]
        public DataSet Ventas(DateTime? desde = null, DateTime? hasta = null)
        {
            Rango(ref desde, ref hasta, 12);
            return new Tablero().Ventas(desde.Value, hasta.Value);
        }

        [HttpGet, Route("api/Tablero/Productos")]
        public DataSet Productos(DateTime? desde = null, DateTime? hasta = null)
        {
            Rango(ref desde, ref hasta, 12);
            return new Tablero().Productos(desde.Value, hasta.Value);
        }

        // GET api/Tablero/Producto/123 — ficha al tocar un producto
        [HttpGet, Route("api/Tablero/Producto/{id:int}")]
        public DataSet Producto(int id)
        {
            return new Tablero().Producto(id);
        }

        [HttpGet, Route("api/Tablero/Proveedores")]
        public DataSet Proveedores(DateTime? desde = null, DateTime? hasta = null)
        {
            Rango(ref desde, ref hasta, 12);
            return new Tablero().Proveedores(desde.Value, hasta.Value);
        }

        [HttpGet, Route("api/Tablero/Clientes")]
        public DataSet Clientes(DateTime? desde = null, DateTime? hasta = null)
        {
            Rango(ref desde, ref hasta, 12);
            return new Tablero().Clientes(desde.Value, hasta.Value);
        }

        // El stock es una foto de hoy: no usa fechas
        [HttpGet, Route("api/Tablero/Stock")]
        public DataSet Stock()
        {
            return new Tablero().Stock();
        }

        [HttpGet, Route("api/Tablero/Rentabilidad")]
        public DataSet Rentabilidad(DateTime? desde = null, DateTime? hasta = null)
        {
            Rango(ref desde, ref hasta, 12);
            return new Tablero().Rentabilidad(desde.Value, hasta.Value);
        }
    }
}
