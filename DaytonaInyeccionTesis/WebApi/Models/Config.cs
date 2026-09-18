using System;
using System.Configuration;

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

        public static string Conexion
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
