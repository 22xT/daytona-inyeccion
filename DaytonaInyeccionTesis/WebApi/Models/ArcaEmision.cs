using System;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Xml.Linq;

namespace WebApi.Models
{
    /* Pedir el CAE de un comprobante (script 93).

       1. Si quedo PENDIENTE de un intento anterior, primero se consulta
          ese numero en ARCA: si ya estaba autorizado, se toma ese CAE.
       2. Si no, se reserva el numero siguiente al ultimo autorizado y
          se manda.
       3. A -> AUTORIZADO con CAE. R -> RECHAZADO con el motivo, y el
          numero se libera. Sin respuesta -> queda PENDIENTE para
          reintentar sin riesgo de duplicar. */
    public class ArcaEmision
    {
        private readonly string _cnn = Config.Conexion;
        private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

        public class Resultado
        {
            public int IdComprobante { get; set; }
            public string Estado { get; set; }
            public string Numero { get; set; }
            public string Cae { get; set; }
            public DateTime? CaeVencimiento { get; set; }
            public string Mensaje { get; set; }
        }

        public Resultado Autorizar(int idComprobante, int idUsuario)
        {
            DataRow conf = Tabla("SP_Arca_Configuracion", null).Rows[0];
            if (conf["IdPuntoVenta"] == DBNull.Value)
                throw new ArcaException("No hay un punto de venta de ARCA configurado (ArcaPuntoVenta).");
            if (!Convert.ToBoolean(conf["Activo"]))
                throw new ArcaException("El punto de venta de ARCA está inactivo.");
            int idPV = Convert.ToInt32(conf["IdPuntoVenta"]);
            int pv = Convert.ToInt32(conf["PuntoVenta"]);
            string entorno = Convert.ToString(conf["Entorno"]);
            string cuitTxt = new string(Convert.ToString(conf["EmisorCuit"]).Where(char.IsDigit).ToArray());
            long cuit;
            if (cuitTxt.Length != 11 || !long.TryParse(cuitTxt, out cuit))
                throw new ArcaException("Falta el CUIT del emisor: completalo en ParametroSistema (EmisorCuit).");

            var arca = new ArcaCliente(entorno, cuit);
            arca.IdUsuario = idUsuario;

            DataSet ds = Datos(idComprobante);
            if (ds.Tables[0].Rows.Count == 0) throw new ArcaException("El comprobante no existe.");
            DataRow c = ds.Tables[0].Rows[0];
            string estado = Convert.ToString(c["Estado"]);
            int tipo = Convert.ToInt32(c["IdTipoComprobante"]);

            if (estado == "AUTORIZADO")
                return Leer(idComprobante, "Ya estaba autorizado.");
            if (estado == "ANULADO")
                throw new ArcaException("El comprobante está anulado.");

            // NC y ND: la factura que corrigen tiene que estar autorizada
            if (c["IdComprobanteAsociado"] != DBNull.Value && Convert.ToString(c["EstadoAsociado"]) != "AUTORIZADO")
                throw new ArcaException("Primero pedí el CAE de la factura que corrige esta nota.");

            long numero = 0;
            DateTime fecha = DateTime.UtcNow.AddHours(-3).Date;   // hora argentina
            bool reenviar = false;

            // 1. Quedo pendiente de un intento anterior
            if (estado == "PENDIENTE")
            {
                int pvC = Convert.ToInt32(c["PuntoVenta"]);
                numero = Convert.ToInt64(c["Numero"]);
                var ya = arca.Consultar(pvC, tipo, numero, idComprobante);
                if (ya != null)
                {
                    if (Math.Abs(ya.Item3 - Convert.ToDecimal(c["ImporteTotal"])) > 0.01m)
                        throw new ArcaException("ARCA tiene autorizado ese número con otro importe (" +
                            ya.Item3.ToString("N2") + "). Revisalo con el contador antes de seguir.");
                    Ejecutar("SP_Arca_Autorizar", cmd =>
                    {
                        cmd.Parameters.Add("@Id", SqlDbType.Int).Value = idComprobante;
                        cmd.Parameters.Add("@Cae", SqlDbType.Char, 14).Value = ya.Item1;
                        cmd.Parameters.Add("@CaeVencimiento", SqlDbType.Date).Value = ya.Item2;
                        cmd.Parameters.Add("@Observaciones", SqlDbType.NVarChar, 500).Value = DBNull.Value;
                    });
                    return Leer(idComprobante, "Ya había quedado autorizado en el intento anterior.");
                }
                long ultimo = arca.UltimoAutorizado(pvC, tipo);
                if (ultimo == numero - 1 && pvC == pv)
                {
                    reenviar = true;                       // mismo numero, misma fecha
                    fecha = Convert.ToDateTime(c["Fecha"]);
                }
                else
                    Rechazar(idComprobante, "Se vuelve a numerar: el número reservado ya no es el siguiente en ARCA.");
            }

            // 2. Numero nuevo
            if (!reenviar)
            {
                numero = arca.UltimoAutorizado(pv, tipo) + 1;
                Ejecutar("SP_Arca_Reservar", cmd =>
                {
                    cmd.Parameters.Add("@Id", SqlDbType.Int).Value = idComprobante;
                    cmd.Parameters.Add("@IdPuntoVenta", SqlDbType.Int).Value = idPV;
                    cmd.Parameters.Add("@Numero", SqlDbType.Int).Value = (int)numero;
                    cmd.Parameters.Add("@Fecha", SqlDbType.Date).Value = fecha;
                });
            }

            // 3. Pedir el CAE
            XElement detalle = Detalle(c, ds.Tables[1], numero, fecha, cuit);
            XElement r;
            try { r = arca.Solicitar(detalle, pv, tipo, idComprobante); }
            catch (ArcaException ex)
            {
                throw new ArcaException(ex.Message + " El comprobante quedó pendiente con el número " +
                    NumeroTexto(pv, numero) + ": al reintentar se consulta primero si ARCA lo autorizó.");
            }

            XNamespace fe = ArcaCliente.Ns;
            XElement det = r.Elements(fe + "FeDetResp").Elements(fe + "FECAEDetResponse").FirstOrDefault();
            string res = det == null ? null : ArcaCliente.Valor(det, "Resultado");
            string obs = det == null ? null : ArcaCliente.Observaciones(det);
            string errores = ArcaCliente.Errores(r);

            if (res == "A")
            {
                string cae = ArcaCliente.Valor(det, "CAE");
                DateTime vto = ArcaCliente.Fecha(ArcaCliente.Valor(det, "CAEFchVto"));
                Ejecutar("SP_Arca_Autorizar", cmd =>
                {
                    cmd.Parameters.Add("@Id", SqlDbType.Int).Value = idComprobante;
                    cmd.Parameters.Add("@Cae", SqlDbType.Char, 14).Value = cae;
                    cmd.Parameters.Add("@CaeVencimiento", SqlDbType.Date).Value = vto;
                    cmd.Parameters.Add("@Observaciones", SqlDbType.NVarChar, 500).Value = (object)obs ?? DBNull.Value;
                });
                return Leer(idComprobante, obs == null ? "Autorizado por ARCA." : "Autorizado con observaciones: " + obs);
            }

            string motivo = string.Join(" | ", new[] { errores, obs }.Where(x => !string.IsNullOrEmpty(x)));
            if (motivo == "") motivo = "ARCA no lo autorizó y no informó el motivo.";
            Rechazar(idComprobante, motivo);
            return Leer(idComprobante, "ARCA lo rechazó: " + motivo);
        }

        /* FECAEDetRequest. El orden de los campos es el del WSDL. */
        private static XElement Detalle(DataRow c, DataTable iva, long numero, DateTime fecha, long cuitEmisor)
        {
            XNamespace fe = ArcaCliente.Ns;
            string clase = Convert.ToString(c["Clase"]);
            var d = new XElement(fe + "FECAEDetRequest",
                new XElement(fe + "Concepto", 1),                          // productos
                new XElement(fe + "DocTipo", Convert.ToInt32(c["ReceptorDocTipo"])),
                new XElement(fe + "DocNro", long.Parse(Convert.ToString(c["ReceptorDocNumero"]), Inv)),
                new XElement(fe + "CbteDesde", numero),
                new XElement(fe + "CbteHasta", numero),
                new XElement(fe + "CbteFch", fecha.ToString("yyyyMMdd")),
                new XElement(fe + "ImpTotal", Imp(c["ImporteTotal"])),
                new XElement(fe + "ImpTotConc", Imp(c["ImporteNoGravado"])),
                new XElement(fe + "ImpNeto", Imp(c["ImporteNeto"])),
                new XElement(fe + "ImpOpEx", Imp(c["ImporteExento"])),
                new XElement(fe + "ImpTrib", Imp(c["ImporteTributos"])),
                new XElement(fe + "ImpIVA", Imp(c["ImporteIva"])),
                new XElement(fe + "MonId", "PES"),
                new XElement(fe + "MonCotiz", 1),
                new XElement(fe + "CondicionIVAReceptorId", Convert.ToInt32(c["ReceptorCondicionIva"])));

            bool esNota = clase != "FC";
            bool conAsociado = c["IdComprobanteAsociado"] != DBNull.Value;
            if (esNota && conAsociado)
                d.Add(new XElement(fe + "CbtesAsoc",
                    new XElement(fe + "CbteAsoc",
                        new XElement(fe + "Tipo", Convert.ToInt32(c["TipoAsociado"])),
                        new XElement(fe + "PtoVta", Convert.ToInt32(c["PuntoVentaAsociado"])),
                        new XElement(fe + "Nro", Convert.ToInt64(c["NumeroAsociado"])),
                        new XElement(fe + "Cuit", cuitEmisor),
                        new XElement(fe + "CbteFch", Convert.ToDateTime(c["FechaAsociado"]).ToString("yyyyMMdd")))));

            if (iva.Rows.Count > 0)
                d.Add(new XElement(fe + "Iva", iva.Rows.Cast<DataRow>().Select(i =>
                    new XElement(fe + "AlicIva",
                        new XElement(fe + "Id", Convert.ToInt32(i["IdArcaIva"])),
                        new XElement(fe + "BaseImp", Imp(i["BaseImponible"])),
                        new XElement(fe + "Importe", Imp(i["Importe"]))))));

            // Nota sin factura en el sistema (venta anterior): se informa el periodo
            if (esNota && !conAsociado)
                d.Add(new XElement(fe + "PeriodoAsoc",
                    new XElement(fe + "FchDesde", new DateTime(fecha.Year, fecha.Month, 1).ToString("yyyyMMdd")),
                    new XElement(fe + "FchHasta", fecha.ToString("yyyyMMdd"))));
            return d;
        }

        private static string Imp(object v) { return Convert.ToDecimal(v).ToString("0.00", Inv); }

        public static string NumeroTexto(int pv, long numero)
        {
            return pv.ToString("00000") + "-" + numero.ToString("00000000");
        }

        /* QR de la RG 4892: JSON en base64 dentro de la URL de ARCA */
        public static string QrUrl(DataRow c, string emisorCuit)
        {
            string cuit = new string((emisorCuit ?? "").Where(char.IsDigit).ToArray());
            if (cuit.Length != 11 || c["Cae"] == DBNull.Value) return null;
            string json = "{\"ver\":1" +
                ",\"fecha\":\"" + Convert.ToDateTime(c["Fecha"]).ToString("yyyy-MM-dd") + "\"" +
                ",\"cuit\":" + cuit +
                ",\"ptoVta\":" + Convert.ToInt32(c["PuntoVenta"]) +
                ",\"tipoCmp\":" + Convert.ToInt32(c["IdTipoComprobante"]) +
                ",\"nroCmp\":" + Convert.ToInt64(c["Numero"]) +
                ",\"importe\":" + Imp(c["ImporteTotal"]) +
                ",\"moneda\":\"PES\",\"ctz\":1" +
                ",\"tipoDocRec\":" + Convert.ToInt32(c["ReceptorDocTipo"]) +
                ",\"nroDocRec\":" + long.Parse(Convert.ToString(c["ReceptorDocNumero"]), Inv) +
                ",\"tipoCodAut\":\"E\",\"codAut\":" + Convert.ToString(c["Cae"]).Trim() + "}";
            return "https://www.afip.gob.ar/fe/qr/?p=" + Convert.ToBase64String(Encoding.UTF8.GetBytes(json));
        }

        /* Estado de la conexion: servidores, certificado, acceso y ultimo numero */
        public object Estado()
        {
            DataRow conf = Tabla("SP_Arca_Configuracion", null).Rows[0];
            var pasos = new System.Collections.Generic.List<object>();
            Action<string, bool, string> paso = (n, ok, t) => pasos.Add(new { Paso = n, Ok = ok, Detalle = t });

            if (conf["IdPuntoVenta"] == DBNull.Value) { paso("Punto de venta", false, "No hay punto de venta de ARCA configurado."); return pasos; }
            string entorno = Convert.ToString(conf["Entorno"]);
            int pv = Convert.ToInt32(conf["PuntoVenta"]);
            paso("Punto de venta", true, pv.ToString("00000") + " · " + (entorno == "PRODUCCION" ? "producción" : "homologación (pruebas)"));

            string cuitTxt = new string(Convert.ToString(conf["EmisorCuit"]).Where(char.IsDigit).ToArray());
            long cuit;
            if (cuitTxt.Length != 11 || !long.TryParse(cuitTxt, out cuit)) { paso("CUIT del emisor", false, "Falta completar EmisorCuit."); return pasos; }
            paso("CUIT del emisor", true, cuitTxt);

            ArcaCliente arca;
            try { arca = new ArcaCliente(entorno, cuit); }
            catch (ArcaException ex) { paso("Configuración", false, ex.Message); return pasos; }

            try { paso("Servidores de ARCA", true, arca.Dummy()); }
            catch (Exception ex) { paso("Servidores de ARCA", false, ex.Message); return pasos; }

            try { paso("Certificado", true, ArcaCliente.DescripcionCertificado()); }
            catch (Exception ex) { paso("Certificado", false, ex.Message); return pasos; }

            try { paso("Acceso y último número", true, "Factura B: último autorizado " + arca.UltimoAutorizado(pv, 6)); }
            catch (Exception ex) { paso("Acceso y último número", false, ex.Message); }
            return pasos;
        }

        /* ---------------- Base ---------------- */

        private void Rechazar(int id, string motivo)
        {
            Ejecutar("SP_Arca_Rechazar", cmd =>
            {
                cmd.Parameters.Add("@Id", SqlDbType.Int).Value = id;
                cmd.Parameters.Add("@Motivo", SqlDbType.NVarChar, 500).Value = motivo.Length > 500 ? motivo.Substring(0, 500) : motivo;
            });
        }

        private Resultado Leer(int id, string mensaje)
        {
            DataRow c = Datos(id).Tables[0].Rows[0];
            return new Resultado
            {
                IdComprobante = id,
                Estado = Convert.ToString(c["Estado"]),
                Numero = c["Numero"] == DBNull.Value ? null : NumeroTexto(Convert.ToInt32(c["PuntoVenta"]), Convert.ToInt64(c["Numero"])),
                Cae = c["Cae"] == DBNull.Value ? null : Convert.ToString(c["Cae"]).Trim(),
                CaeVencimiento = c["CaeVencimiento"] == DBNull.Value ? (DateTime?)null : Convert.ToDateTime(c["CaeVencimiento"]),
                Mensaje = mensaje
            };
        }

        private DataSet Datos(int id)
        {
            using (var cnn = new SqlConnection(_cnn))
            using (var cmd = new SqlCommand("SP_Arca_Comprobante", cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@Id", SqlDbType.Int).Value = id;
                var ds = new DataSet();
                using (var da = new SqlDataAdapter(cmd)) { cnn.Open(); da.Fill(ds); }
                return ds;
            }
        }

        private DataTable Tabla(string sp, Action<SqlCommand> parametros)
        {
            using (var cnn = new SqlConnection(_cnn))
            using (var cmd = new SqlCommand(sp, cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                if (parametros != null) parametros(cmd);
                var dt = new DataTable();
                using (var da = new SqlDataAdapter(cmd)) { cnn.Open(); da.Fill(dt); }
                return dt;
            }
        }

        private void Ejecutar(string sp, Action<SqlCommand> parametros)
        {
            using (var cnn = new SqlConnection(_cnn))
            using (var cmd = new SqlCommand(sp, cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                parametros(cmd);
                cnn.Open();
                cmd.ExecuteNonQuery();
            }
        }
    }
}
