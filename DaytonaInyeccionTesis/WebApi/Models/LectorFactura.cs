using System;
using System.Configuration;
using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;

namespace WebApi.Models
{
    /* Lee la foto o el PDF de una factura de proveedor con un modelo de
       vision (Claude) y devuelve los datos en JSON.

       Solo LEE: no toca la base. Lo que devuelve es una propuesta que la
       persona revisa antes de confirmar la recepcion.

       Configuracion en Web.config (appSettings), fuera de Git:
         Anthropic:ApiKey   la clave de la API
         Anthropic:Model    opcional, por defecto claude-sonnet-5-5
       Sin clave, la lectura no esta disponible y la recepcion manual
       sigue funcionando igual. */
    public class LectorFactura
    {
        private const string Url = "https://api.anthropic.com/v1/messages";
        private const string ModeloPorDefecto = "claude-sonnet-5-5";

        // Un solo HttpClient para toda la aplicacion: crear uno por pedido agota los sockets
        private static readonly HttpClient http;

        static LectorFactura()
        {
            // .NET Framework 4.5 no usa TLS 1.2 por defecto, y la API lo exige
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            http = new HttpClient();
            http.Timeout = TimeSpan.FromSeconds(90);
        }

        public static string ApiKey { get { return ConfigurationManager.AppSettings["Anthropic:ApiKey"]; } }

        public static string Modelo
        {
            get
            {
                string m = ConfigurationManager.AppSettings["Anthropic:Model"];
                return string.IsNullOrWhiteSpace(m) ? ModeloPorDefecto : m.Trim();
            }
        }

        public static bool Configurado { get { return !string.IsNullOrWhiteSpace(ApiKey); } }

        public class Resultado
        {
            public bool Exito;
            public string Error;
            public string Texto;       // la respuesta cruda del modelo
            public JObject Factura;    // ya parseada
            public int DuracionMs;
        }

        private const string Instrucciones =
@"Sos un asistente que transcribe facturas, presupuestos y remitos de proveedores de repuestos automotores de Argentina.
Leé la factura de la imagen y devolvé SOLO un objeto JSON, sin texto antes ni después y sin bloques de código, con esta forma exacta:

{
  ""proveedor"": ""razón social del emisor"",
  ""tipoComprobante"": ""Factura A"" | ""Factura B"" | ""Factura C"" | ""Presupuesto"" | ""Remito"" | null,
  ""numero"": ""punto de venta y número, ej 0003-00045678"",
  ""fecha"": ""AAAA-MM-DD"",
  ""total"": número,
  ""renglones"": [
    { ""codigo"": ""código del artículo tal cual figura"", ""descripcion"": ""texto del renglón"", ""cantidad"": número, ""precioUnitario"": número }
  ]
}

Reglas:
- Los números van con punto decimal y sin separador de miles: 36131.51, no 36.131,51.
- precioUnitario es el precio de una unidad después de descuentos y SIN IVA, si la factura lo muestra. Si solo figura el importe del renglón, dividilo por la cantidad.
- total es el total final del comprobante, con impuestos.
- Copiá los códigos exactamente como aparecen, con guiones y letras.
- Si un dato no se lee o no está, poné null. No inventes nada.
- Un renglón por artículo. Ignorá subtotales, percepciones, IVA y leyendas.";

        public async Task<Resultado> Leer(byte[] contenido, string mime)
        {
            var r = new Resultado();
            var reloj = Stopwatch.StartNew();
            try
            {
                string b64 = Convert.ToBase64String(contenido);

                // La imagen va antes del texto: es como mejor trabaja el modelo
                JObject bloqueArchivo = mime == "application/pdf"
                    ? new JObject(
                        new JProperty("type", "document"),
                        new JProperty("source", new JObject(
                            new JProperty("type", "base64"),
                            new JProperty("media_type", "application/pdf"),
                            new JProperty("data", b64))))
                    : new JObject(
                        new JProperty("type", "image"),
                        new JProperty("source", new JObject(
                            new JProperty("type", "base64"),
                            new JProperty("media_type", mime),
                            new JProperty("data", b64))));

                JObject cuerpo = new JObject(
                    new JProperty("model", Modelo),
                    new JProperty("max_tokens", 4000),
                    new JProperty("messages", new JArray(
                        new JObject(
                            new JProperty("role", "user"),
                            new JProperty("content", new JArray(
                                bloqueArchivo,
                                new JObject(new JProperty("type", "text"), new JProperty("text", Instrucciones))))))));

                using (var req = new HttpRequestMessage(HttpMethod.Post, Url))
                {
                    req.Headers.Add("x-api-key", ApiKey);
                    req.Headers.Add("anthropic-version", "2023-06-01");
                    req.Content = new StringContent(cuerpo.ToString(), Encoding.UTF8, "application/json");

                    using (HttpResponseMessage resp = await http.SendAsync(req))
                    {
                        string json = await resp.Content.ReadAsStringAsync();
                        if (!resp.IsSuccessStatusCode)
                        {
                            r.Error = "La API respondió " + (int)resp.StatusCode + ": " + Recortar(json, 300);
                            return r;
                        }

                        JObject respuesta = JObject.Parse(json);
                        var sb = new StringBuilder();
                        foreach (JToken bloque in respuesta["content"])
                            if ((string)bloque["type"] == "text") sb.Append((string)bloque["text"]);
                        r.Texto = sb.ToString().Trim();
                    }
                }

                // Por si el modelo envolvio el JSON en un bloque de codigo
                string limpio = r.Texto;
                int ini = limpio.IndexOf('{'), fin = limpio.LastIndexOf('}');
                if (ini < 0 || fin <= ini) { r.Error = "La respuesta no trajo un JSON."; return r; }
                limpio = limpio.Substring(ini, fin - ini + 1);

                r.Factura = JObject.Parse(limpio);
                r.Exito = true;
            }
            catch (TaskCanceledException) { r.Error = "La lectura tardó demasiado. Probá de nuevo o cargá la factura a mano."; }
            catch (HttpRequestException ex) { r.Error = "No se pudo conectar con el servicio de lectura: " + ex.Message; }
            catch (Exception ex) { r.Error = "No se pudo interpretar la lectura: " + ex.Message; }
            finally { r.DuracionMs = (int)reloj.ElapsedMilliseconds; }
            return r;
        }

        private static string Recortar(string s, int max)
        {
            if (s == null) return "";
            return s.Length <= max ? s : s.Substring(0, max) + "…";
        }
    }
}
