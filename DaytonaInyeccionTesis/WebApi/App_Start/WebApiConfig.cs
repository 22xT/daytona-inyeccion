using System;
using System.Linq;
using System.Web.Http;
using System.Web.Http.Cors;
using WebApi.Models;

namespace WebApi
{
    public static class WebApiConfig
    {
        public static void Register(HttpConfiguration config)
        {
            /* CORS

               Antes el origen estaba fijo en "http://127.0.0.1:5500".
               Eso funciona en desarrollo, pero al publicar en Azure el
               frontend queda en otra direccion y el navegador rechaza
               todas las llamadas sin decir por que: en la consola solo
               aparece un error de CORS y parece que la API esta caida.

               Ahora sale de Web.config y se cambia sin recompilar. Acepta
               varios origenes separados por coma, para poder tener a la
               vez el sitio publicado y la app mobile en desarrollo. */

            var origenes = Config.OrigenesPermitidos;

            var cors = new EnableCorsAttribute(origenes, "*", "*");
            config.EnableCors(cors);

            // Rutas por atributo, para los [Route] de los controllers
            config.MapHttpAttributeRoutes();

            config.Routes.MapHttpRoute(
                name: "DefaultApi",
                routeTemplate: "api/{controller}/{id}",
                defaults: new { id = RouteParameter.Optional }
            );
        }
    }
}