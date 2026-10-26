using System;
using System.Collections.Concurrent;
using System.Configuration;
using System.Data.SqlClient;
using System.Security.Claims;
using System.Threading;
using System.Web;

namespace WebApi.Models
{
    /* =============================================================
       Config — unico punto de acceso a la configuracion

       ANTES
       La cadena de conexion estaba escrita adentro de cada modelo,
       repetida en quince archivos, con Integrated Security. Cambiar
       de servidor obligaba a editar los quince, y era cuestion de
       tiempo que alguno quedara apuntando al lugar equivocado.

       Ademas, en Azure la autenticacion integrada de Windows no
       existe: va usuario y contraseña. Con la cadena en el codigo,
       eso significaba tocar quince archivos otra vez.

       AHORA
       El valor vive en Web.config, y en Azure se reemplaza desde la
       configuracion del App Service. El secreto deja de viajar en el
       repositorio.
       ============================================================= */
    public static class Config
    {
        // Se cachea: leer el Web.config en cada consulta es innecesario
        private static string _conexion;

        /* AUDITORIA (script 83)
           Cada conexion lleva el usuario de la sesion en el nombre de
           aplicacion: "Daytona#u=<IdUsuario>". Los disparadores de la base
           lo leen con APP_NAME() y saben quien hizo cada cambio, sin tener
           que pasar el usuario a mano en cada modelo. Sin sesion (login,
           tareas internas) va la cadena tal cual. */
        private static readonly ConcurrentDictionary<int, string> _porUsuario =
            new ConcurrentDictionary<int, string>();

        public static string Conexion
        {
            get
            {
                string cadena = ConexionBase;
                int idUsuario = UsuarioDeLaSesion();
                if (idUsuario <= 0) return cadena;
                return _porUsuario.GetOrAdd(idUsuario, id =>
                {
                    var b = new SqlConnectionStringBuilder(cadena);
                    b.ApplicationName = "Daytona#u=" + id;
                    return b.ConnectionString;
                });
            }
        }

        private static int UsuarioDeLaSesion()
        {
            try
            {
                ClaimsPrincipal p = null;
                if (HttpContext.Current != null) p = HttpContext.Current.User as ClaimsPrincipal;
                if (p == null) p = Thread.CurrentPrincipal as ClaimsPrincipal;
                if (p == null) return 0;
                Claim c = p.FindFirst(ClaimTypes.NameIdentifier) ?? p.FindFirst("sub") ?? p.FindFirst("Sub");
                int id;
                return c != null && int.TryParse(c.Value, out id) ? id : 0;
            }
            catch
            {
                return 0;
            }
        }

        private static string ConexionBase
        {
            get
            {
                if (_conexion != null) return _conexion;

                var cs = ConfigurationManager.ConnectionStrings["DaytonaDB"];

                if (cs == null || string.IsNullOrWhiteSpace(cs.ConnectionString))
                    throw new ConfigurationErrorsException(
                        "Falta la cadena de conexión 'DaytonaDB' en Web.config.");

                _conexion = cs.ConnectionString;
                return _conexion;
            }
        }

        // Origenes permitidos para CORS, separados por coma.
        // En Azure se cambia sin recompilar.
        public static string OrigenesPermitidos
        {
            get
            {
                var v = ConfigurationManager.AppSettings["Cors:Origenes"];
                return string.IsNullOrWhiteSpace(v) ? "*" : v;
            }
        }

        public static string JwtSecretKey
        {
            get { return ConfigurationManager.AppSettings["Jwt:SecretKey"]; }
        }

        public static string JwtIssuer
        {
            get { return ConfigurationManager.AppSettings["Jwt:Issuer"]; }
        }

        public static string JwtAudience
        {
            get { return ConfigurationManager.AppSettings["Jwt:Audience"]; }
        }

        public static int JwtExpirationHours
        {
            get
            {
                int h;
                var v = ConfigurationManager.AppSettings["Jwt:ExpirationHours"];
                return int.TryParse(v, out h) && h > 0 ? h : 8;
            }
        }
    }
}
