using System;
using System.Data;
using System.Data.SqlClient;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class ConfiguracionController : ApiController
    {
        // GET: api/Configuracion/Parametros
        [HttpGet]
        [Route("api/Configuracion/Parametros")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public DataTable Parametros()
        {
            Configuracion oConf = new Configuracion();
            return oConf.ListarParametros();
        }

        // PUT: api/Configuracion/Parametro
        // El margen y los descuentos son decisiones comerciales:
        // solo Dueño y Administrador los cambian.
        [HttpPut]
        [Route("api/Configuracion/Parametro")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult GuardarParametro([FromBody] Configuracion conf)
        {
            if (conf == null || string.IsNullOrEmpty(conf.Clave))
                return BadRequest("Falta indicar el parametro.");

            try
            {
                conf.GuardarParametro();
                return Ok();
            }
            catch (SqlException ex)
            {
                if (ex.Number >= 50000)
                    return BadRequest(ex.Message);
                return BadRequest("No se pudo guardar el parametro.");
            }
        }

        /* GET: api/Configuracion/Venta
           Solo los parametros que hacen falta en el mostrador.

           No se abre el endpoint general a los vendedores porque ahi
           vive el margen de ganancia, que es informacion comercial
           sensible. Este devuelve unicamente los descuentos. */
        [HttpGet]
        [Route("api/Configuracion/Venta")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult ParametrosVenta()
        {
            Configuracion oConf = new Configuracion();
            DataTable dt = oConf.ListarParametros();

            string descuentosPublico = "5,7,10";
            string descuentoMecanico = "10";

            foreach (DataRow fila in dt.Rows)
            {
                string clave = Convert.ToString(fila["Clave"]);
                string valor = Convert.ToString(fila["Valor"]);

                if (clave == "DescuentosPublico") descuentosPublico = valor;
                if (clave == "DescuentoMecanico") descuentoMecanico = valor;
            }

            return Ok(new
            {
                DescuentosPublico = descuentosPublico,
                DescuentoMecanico = descuentoMecanico
            });
        }

        // GET: api/Configuracion/Margenes?soloConMargen=true&texto=amorti
        [HttpGet]
        [Route("api/Configuracion/Margenes")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public DataTable Margenes(bool soloConMargen = true, string texto = null)
        {
            Configuracion oConf = new Configuracion();
            return oConf.ListarMargenes(soloConMargen, texto);
        }

        // PUT: api/Configuracion/Margen
        // Margen null borra la excepcion y el rubro vuelve al general.
        [HttpPut]
        [Route("api/Configuracion/Margen")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult GuardarMargen([FromBody] Configuracion conf)
        {
            if (conf == null || conf.IdRubro <= 0)
                return BadRequest("Falta indicar el rubro.");

            try
            {
                conf.GuardarMargen();
                return Ok();
            }
            catch (SqlException ex)
            {
                if (ex.Number >= 50000)
                    return BadRequest(ex.Message);
                return BadRequest("No se pudo guardar el margen.");
            }
        }
    }
}
