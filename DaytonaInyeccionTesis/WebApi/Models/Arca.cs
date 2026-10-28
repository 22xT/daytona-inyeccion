using System;
using System.Configuration;
using System.Data;
using System.Data.SqlClient;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Security.Cryptography.Pkcs;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace WebApi.Models
{
    /* =============================================================
       ARCA — conexion con los servicios web de factura electronica

       WSAA  : login con el certificado. Devuelve token y firma que
               duran 12 horas; se guardan en la base (ArcaToken)
               porque ARCA no da otro mientras el anterior siga vigente.
       WSFEv1: ultimo numero autorizado, pedir CAE y consultar.

       El certificado (.pfx) y su clave NUNCA van al repositorio.
       Se configuran en Web.config (o en la configuracion del App
       Service en Azure):
         Arca:CertPath      ruta del .pfx
         Arca:CertPassword  clave del .pfx
       El CUIT del emisor sale de ParametroSistema (EmisorCuit).
       ============================================================= */
    public class ArcaException : Exception
    {
        public ArcaException(string mensaje) : base(mensaje) { }
    }

    public class ArcaCliente
    {
        private const string NsFe = "http://ar.gov.afip.dif.FEV1/";
        private static readonly XNamespace Fe = NsFe;
        private static readonly XNamespace Soap = "http://schemas.xmlsoap.org/soap/envelope/";
        private static readonly object _bloqueo = new object();
        private static X509Certificate2 _certificado;

        private readonly string _cnn = Config.Conexion;

        public string Entorno { get; private set; }     // HOMOLOGACION | PRODUCCION
        public long Cuit { get; private set; }
        public int? IdUsuario { get; set; }

        public ArcaCliente(string entorno, long cuit)
        {
            if (entorno != "HOMOLOGACION" && entorno != "PRODUCCION")
                throw new ArcaException("El punto de venta configurado no es de ARCA (homologación o producción).");
            if (cuit <= 0)
                throw new ArcaException("Falta el CUIT del emisor (Configuración: EmisorCuit).");
            Entorno = entorno;
            Cuit = cuit;
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
        }

        private string UrlWsaa
        {
            get
            {
                return Entorno == "PRODUCCION"
                    ? "https://wsaa.afip.gov.ar/ws/services/LoginCms"
                    : "https://wsaahomo.afip.gov.ar/ws/services/LoginCms";
            }
        }

        private string UrlWsfe
        {
            get
            {
                return Entorno == "PRODUCCION"
                    ? "https://servicios1.afip.gov.ar/wsfev1/service.asmx"
                    : "https://wswhomo.afip.gov.ar/wsfev1/service.asmx";
            }
        }

        /* ---------------- Certificado ---------------- */

        private static X509Certificate2 Certificado()
        {
            lock (_bloqueo)
            {
                if (_certificado != null && _certificado.NotAfter > DateTime.Now) return _certificado;

                string ruta = ConfigurationManager.AppSettings["Arca:CertPath"];
                string clave = ConfigurationManager.AppSettings["Arca:CertPassword"];
                if (string.IsNullOrWhiteSpace(ruta))
                    throw new ArcaException("Falta configurar el certificado de ARCA (Arca:CertPath).");
                if (!Path.IsPathRooted(ruta))
                    ruta = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ruta);
                if (!File.Exists(ruta))
                    throw new ArcaException("No se encuentra el certificado de ARCA en la ruta configurada.");

                // MachineKeySet: en IIS y en Azure no hay perfil de usuario cargado
                var cert = new X509Certificate2(ruta, clave ?? "", X509KeyStorageFlags.MachineKeySet);
                if (!cert.HasPrivateKey)
                    throw new ArcaException("El certificado de ARCA no tiene la clave privada (tiene que ser el .pfx).");
                if (cert.NotAfter < DateTime.Now)
                    throw new ArcaException("El certificado de ARCA está vencido (" + cert.NotAfter.ToString("dd/MM/yyyy") + ").");
                _certificado = cert;
                return cert;
            }
        }

        public static string DescripcionCertificado()
        {
            var c = Certificado();
            return c.Subject + " · vence " + c.NotAfter.ToString("dd/MM/yyyy");
        }

        /* ---------------- WSAA: ticket de acceso ---------------- */

        private Tuple<string, string> Credenciales()
        {
            lock (_bloqueo)
            {
                // 1. El guardado, si le quedan al menos 10 minutos
                using (var cnn = new SqlConnection(_cnn))
                using (var cmd = new SqlCommand("SP_ArcaToken_Get", cnn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@Servicio", SqlDbType.VarChar, 20).Value = "wsfe";
                    cmd.Parameters.Add("@Entorno", SqlDbType.VarChar, 13).Value = Entorno;
                    cnn.Open();
                    using (var dr = cmd.ExecuteReader())
                    {
                        if (dr.Read() && Convert.ToDateTime(dr["ExpiraUtc"]) > DateTime.UtcNow.AddMinutes(10))
                            return Tuple.Create(Convert.ToString(dr["Token"]), Convert.ToString(dr["Sign"]));
                    }
                }

                // 2. Uno nuevo
                string tra = new XElement("loginTicketRequest", new XAttribute("version", "1.0"),
                    new XElement("header",
                        new XElement("uniqueId", (long)(DateTime.UtcNow - new DateTime(1970, 1, 1)).TotalSeconds),
                        new XElement("generationTime", DateTime.UtcNow.AddMinutes(-10).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")),
                        new XElement("expirationTime", DateTime.UtcNow.AddMinutes(10).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"))),
                    new XElement("service", "wsfe")).ToString(SaveOptions.DisableFormatting);

                var cms = new SignedCms(new ContentInfo(Encoding.UTF8.GetBytes(tra)));
                var firmante = new CmsSigner(Certificado());
                firmante.IncludeOption = X509IncludeOption.EndCertOnly;
                cms.ComputeSignature(firmante);
                string cmsBase64 = Convert.ToBase64String(cms.Encode());

                string sobre =
                    "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" " +
                    "xmlns:wsaa=\"http://wsaa.view.sua.dvadac.desein.afip.gov\"><soapenv:Header/><soapenv:Body>" +
                    "<wsaa:loginCms><wsaa:in0>" + cmsBase64 + "</wsaa:in0></wsaa:loginCms></soapenv:Body></soapenv:Envelope>";

                var reloj = Stopwatch.StartNew();
                string respuesta;
                try { respuesta = Enviar(UrlWsaa, "\"\"", sobre); }
                catch (ArcaException ex)
                {
                    Registrar("WSAA", "loginCms", null, "ERROR", ex.Message, null, null, reloj);
                    throw;
                }

                XDocument doc = XDocument.Parse(respuesta);
                string falla = Falla(doc);
                if (falla != null)
                {
                    Registrar("WSAA", "loginCms", null, "ERROR", falla, null, null, reloj);
                    if (falla.IndexOf("TA valido", StringComparison.OrdinalIgnoreCase) >= 0)
                        throw new ArcaException("ARCA ya entregó un acceso que sigue vigente y se perdió. Hay que esperar a que venza (hasta 12 horas) o generar otro certificado.");
                    throw new ArcaException("ARCA rechazó el ingreso: " + falla);
                }

                string ticketXml = doc.Descendants().First(e => e.Name.LocalName == "loginCmsReturn").Value;
                XDocument ticket = XDocument.Parse(ticketXml);
                string token = ticket.Descendants("token").First().Value;
                string sign = ticket.Descendants("sign").First().Value;
                DateTime expira = DateTime.Parse(ticket.Descendants("expirationTime").First().Value,
                                                 CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal);

                using (var cnn = new SqlConnection(_cnn))
                using (var cmd = new SqlCommand("SP_ArcaToken_Set", cnn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@Servicio", SqlDbType.VarChar, 20).Value = "wsfe";
                    cmd.Parameters.Add("@Entorno", SqlDbType.VarChar, 13).Value = Entorno;
                    cmd.Parameters.Add("@Token", SqlDbType.NVarChar, -1).Value = token;
                    cmd.Parameters.Add("@Sign", SqlDbType.NVarChar, -1).Value = sign;
                    cmd.Parameters.Add("@ExpiraUtc", SqlDbType.DateTime).Value = expira;
                    cnn.Open();
                    cmd.ExecuteNonQuery();
                }
                Registrar("WSAA", "loginCms", null, "OK", "Acceso vigente hasta " + expira.AddHours(-3).ToString("dd/MM HH:mm"), null, null, reloj);
                return Tuple.Create(token, sign);
            }
        }

        /* ---------------- WSFEv1 ---------------- */

        private XElement Auth()
        {
            var c = Credenciales();
            return new XElement(Fe + "Auth",
                new XElement(Fe + "Token", c.Item1),
                new XElement(Fe + "Sign", c.Item2),
                new XElement(Fe + "Cuit", Cuit));
        }

        // Llama un metodo y devuelve su "...Result". Errores de ARCA quedan en el resultado.
        private XElement Llamar(string metodo, XElement cuerpo, int? idComprobante, bool conAuth)
        {
            if (conAuth) cuerpo.AddFirst(Auth());
            var sobre = new XDocument(new XElement(Soap + "Envelope",
                new XAttribute(XNamespace.Xmlns + "soap", Soap.NamespaceName),
                new XAttribute(XNamespace.Xmlns + "ar", NsFe),
                new XElement(Soap + "Body", cuerpo)));
            string enviado = sobre.ToString(SaveOptions.DisableFormatting);

            var reloj = Stopwatch.StartNew();
            string recibido;
            try { recibido = Enviar(UrlWsfe, "\"" + NsFe + metodo + "\"", enviado); }
            catch (ArcaException ex)
            {
                Registrar("WSFE", metodo, idComprobante, "ERROR", ex.Message, SinCredenciales(enviado), null, reloj);
                throw;
            }

            XDocument doc = XDocument.Parse(recibido);
            string falla = Falla(doc);
            XElement resultado = doc.Descendants(Fe + metodo + "Result").FirstOrDefault();
            string errores = resultado == null ? null : Errores(resultado);
            // FECAESolicitar trae A (aprobado), R (rechazado) o P (parcial) en la cabecera
            XElement cab = resultado == null ? null : resultado.Element(Fe + "FeCabResp");
            string res = falla != null || resultado == null ? "ERROR"
                       : (cab != null && Valor(cab, "Resultado") != null ? Valor(cab, "Resultado")
                          : (errores != null ? "ERROR" : "OK"));
            Registrar("WSFE", metodo, idComprobante, res, falla ?? errores, SinCredenciales(enviado), recibido, reloj);

            if (falla != null) throw new ArcaException("ARCA respondió con un error: " + falla);
            if (resultado == null) throw new ArcaException("ARCA devolvió una respuesta que no se pudo leer.");
            return resultado;
        }

        // Prueba de vida de los servidores (no usa el certificado)
        public string Dummy()
        {
            XElement r = Llamar("FEDummy", new XElement(Fe + "FEDummy"), null, false);
            return "App " + Valor(r, "AppServer") + " · Base " + Valor(r, "DbServer") + " · Login " + Valor(r, "AuthServer");
        }

        public long UltimoAutorizado(int puntoVenta, int tipo)
        {
            XElement r = Llamar("FECompUltimoAutorizado", new XElement(Fe + "FECompUltimoAutorizado",
                new XElement(Fe + "PtoVta", puntoVenta),
                new XElement(Fe + "CbteTipo", tipo)), null, true);
            string err = Errores(r);
            if (err != null) throw new ArcaException("ARCA no informó el último número: " + err);
            return long.Parse(Valor(r, "CbteNro") ?? "0", CultureInfo.InvariantCulture);
        }

        // Si ese numero ya esta autorizado devuelve (CAE, vencimiento, total); si no existe, null
        public Tuple<string, DateTime, decimal> Consultar(int puntoVenta, int tipo, long numero, int? idComprobante)
        {
            XElement r = Llamar("FECompConsultar", new XElement(Fe + "FECompConsultar",
                new XElement(Fe + "FeCompConsReq",
                    new XElement(Fe + "CbteTipo", tipo),
                    new XElement(Fe + "CbteNro", numero),
                    new XElement(Fe + "PtoVta", puntoVenta))), idComprobante, true);
            XElement get = r.Element(Fe + "ResultGet");
            if (get == null || string.IsNullOrEmpty(Valor(get, "CodAutorizacion")))
            {
                string err = Errores(r);
                // 602: no existe el comprobante. Cualquier otro error se informa.
                if (err != null && !err.StartsWith("602")) throw new ArcaException("No se pudo consultar en ARCA: " + err);
                return null;
            }
            return Tuple.Create(Valor(get, "CodAutorizacion"), Fecha(Valor(get, "FchVto")),
                                decimal.Parse(Valor(get, "ImpTotal"), CultureInfo.InvariantCulture));
        }

        public XElement Solicitar(XElement detalle, int puntoVenta, int tipo, int idComprobante)
        {
            return Llamar("FECAESolicitar", new XElement(Fe + "FECAESolicitar",
                new XElement(Fe + "FeCAEReq",
                    new XElement(Fe + "FeCabReq",
                        new XElement(Fe + "CantReg", 1),
                        new XElement(Fe + "PtoVta", puntoVenta),
                        new XElement(Fe + "CbteTipo", tipo)),
                    new XElement(Fe + "FeDetReq", detalle))), idComprobante, true);
        }

        public static XNamespace Ns { get { return Fe; } }

        /* ---------------- Utilidades ---------------- */

        private static string Enviar(string url, string accion, string cuerpo)
        {
            var req = (HttpWebRequest)WebRequest.Create(url);
            req.Method = "POST";
            req.ContentType = "text/xml; charset=utf-8";
            req.Headers.Add("SOAPAction", accion);
            req.Timeout = 30000;
            req.ReadWriteTimeout = 30000;
            byte[] datos = Encoding.UTF8.GetBytes(cuerpo);
            try
            {
                using (var s = req.GetRequestStream()) s.Write(datos, 0, datos.Length);
                using (var resp = (HttpWebResponse)req.GetResponse())
                using (var lector = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                    return lector.ReadToEnd();
            }
            catch (WebException ex)
            {
                // Un SOAP Fault llega como HTTP 500 con el detalle en el cuerpo
                if (ex.Response != null)
                {
                    using (var lector = new StreamReader(ex.Response.GetResponseStream(), Encoding.UTF8))
                    {
                        string txt = lector.ReadToEnd();
                        if (txt.Contains("Envelope")) return txt;
                    }
                }
                throw new ArcaException("No se pudo conectar con ARCA (" + ex.Status + "). Puede ser un corte momentáneo: reintentá en unos minutos.");
            }
        }

        private static string Falla(XDocument doc)
        {
            XElement f = doc.Descendants().FirstOrDefault(e => e.Name.LocalName == "Fault");
            if (f == null) return null;
            XElement s = f.Descendants().FirstOrDefault(e => e.Name.LocalName == "faultstring");
            return s != null ? s.Value : "Error SOAP";
        }

        public static string Errores(XElement resultado)
        {
            var errs = resultado.Elements(Fe + "Errors").Elements(Fe + "Err")
                .Select(e => Valor(e, "Code") + " " + Valor(e, "Msg")).ToList();
            return errs.Count == 0 ? null : string.Join(" | ", errs);
        }

        public static string Observaciones(XElement detalle)
        {
            var obs = detalle.Elements(Fe + "Observaciones").Elements(Fe + "Obs")
                .Select(e => Valor(e, "Code") + " " + Valor(e, "Msg")).ToList();
            return obs.Count == 0 ? null : string.Join(" | ", obs);
        }

        public static string Valor(XElement padre, string nombre)
        {
            XElement e = padre.Element(Fe + nombre);
            return e == null ? null : e.Value;
        }

        public static DateTime Fecha(string aaaammdd)
        {
            return DateTime.ParseExact(aaaammdd, "yyyyMMdd", CultureInfo.InvariantCulture);
        }

        // El token y la firma no se guardan nunca en el registro
        private static string SinCredenciales(string xml)
        {
            xml = Regex.Replace(xml, "<ar:Token>.*?</ar:Token>", "<ar:Token>***</ar:Token>", RegexOptions.Singleline);
            return Regex.Replace(xml, "<ar:Sign>.*?</ar:Sign>", "<ar:Sign>***</ar:Sign>", RegexOptions.Singleline);
        }

        private void Registrar(string servicio, string metodo, int? idComprobante, string resultado, string mensaje,
                               string enviado, string recibido, Stopwatch reloj)
        {
            try
            {
                using (var cnn = new SqlConnection(_cnn))
                using (var cmd = new SqlCommand("SP_ArcaSolicitud_I", cnn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.Add("@Entorno", SqlDbType.VarChar, 13).Value = Entorno;
                    cmd.Parameters.Add("@Servicio", SqlDbType.VarChar, 20).Value = servicio;
                    cmd.Parameters.Add("@Metodo", SqlDbType.VarChar, 40).Value = metodo;
                    cmd.Parameters.Add("@IdComprobante", SqlDbType.Int).Value = idComprobante.HasValue ? (object)idComprobante.Value : DBNull.Value;
                    cmd.Parameters.Add("@Resultado", SqlDbType.VarChar, 10).Value = resultado;
                    cmd.Parameters.Add("@Mensaje", SqlDbType.NVarChar, 2000).Value = (object)mensaje ?? DBNull.Value;
                    cmd.Parameters.Add("@Enviado", SqlDbType.NVarChar, -1).Value = (object)enviado ?? DBNull.Value;
                    cmd.Parameters.Add("@Recibido", SqlDbType.NVarChar, -1).Value = (object)recibido ?? DBNull.Value;
                    cmd.Parameters.Add("@DuracionMs", SqlDbType.Int).Value = (int)reloj.ElapsedMilliseconds;
                    cmd.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = IdUsuario.HasValue ? (object)IdUsuario.Value : DBNull.Value;
                    cnn.Open();
                    cmd.ExecuteNonQuery();
                }
            }
            catch { /* el registro nunca hace fallar el pedido */ }
        }
    }
}
