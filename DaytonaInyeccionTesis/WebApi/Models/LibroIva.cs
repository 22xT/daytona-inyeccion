using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.Linq;
using System.Text;

namespace WebApi.Models
{
    /* Libro IVA ventas y compras (script 96) y los archivos para importar
       en Libro IVA Digital de ARCA (RG 4597): ancho fijo, importes de 15
       posiciones sin separador (13 enteros y 2 decimales), fechas AAAAMMDD,
       numericos con ceros a la izquierda, textos con espacios a la derecha,
       codificacion ANSI (Windows-1252), un comprobante por linea.

         Ventas comprobantes   266   Ventas alicuotas    62
         Compras comprobantes  325   Compras alicuotas   84

       Conviene que el contador valide la primera importacion. */
    public class LibroIva
    {
        private readonly string _cnn = Config.Conexion;

        public DataSet Ventas(DateTime desde, DateTime hasta, bool pruebas)
        {
            return Ejecutar("SP_LibroIva_Ventas", desde, hasta, pruebas);
        }

        public DataSet Compras(DateTime desde, DateTime hasta)
        {
            return Ejecutar("SP_LibroIva_Compras", desde, hasta, null);
        }

        public DataSet Faltantes(DateTime desde, DateTime hasta, bool pruebas)
        {
            return Ejecutar("SP_LibroIva_Faltantes", desde, hasta, pruebas);
        }

        /* ---------------- Archivos de Libro IVA Digital ---------------- */

        // archivo: ventas-cbte | ventas-alicuotas | compras-cbte | compras-alicuotas
        public byte[] Archivo(string archivo, DateTime desde, DateTime hasta)
        {
            var sb = new StringBuilder();
            if (archivo.StartsWith("ventas"))
            {
                DataSet ds = Ventas(desde, hasta, false);
                ILookup<int, DataRow> iva = ds.Tables[1].Rows.Cast<DataRow>().ToLookup(r => Convert.ToInt32(r["IdComprobante"]));
                foreach (DataRow c in ds.Tables[0].Rows)
                {
                    List<DataRow> alic = iva[Convert.ToInt32(c["Id"])].ToList();
                    if (archivo == "ventas-cbte") sb.Append(VentaCbte(c, alic)).Append("\r\n");
                    else foreach (string l in VentaAlicuotas(c, alic)) sb.Append(l).Append("\r\n");
                }
            }
            else
            {
                DataSet ds = Compras(desde, hasta);
                ILookup<int, DataRow> iva = ds.Tables[1].Rows.Cast<DataRow>().ToLookup(r => Convert.ToInt32(r["IdCompraFiscal"]));
                foreach (DataRow c in ds.Tables[0].Rows)
                {
                    List<DataRow> alic = iva[Convert.ToInt32(c["Id"])].ToList();
                    if (archivo == "compras-cbte") sb.Append(CompraCbte(c, alic)).Append("\r\n");
                    else foreach (string l in CompraAlicuotas(c, alic)) sb.Append(l).Append("\r\n");
                }
            }
            return Encoding.GetEncoding(1252).GetBytes(sb.ToString());
        }

        private static string VentaCbte(DataRow c, List<DataRow> alic)
        {
            int docTipo = Convert.ToInt32(c["ReceptorDocTipo"]);
            string nombre = docTipo == 99 ? "CONSUMIDOR FINAL" : Convert.ToString(c["ReceptorNombre"]);
            decimal exento = D(c["ImporteExento"]);
            var s = new StringBuilder();
            s.Append(F(c["Fecha"]));
            s.Append(N(c["TipoArca"], 3));
            s.Append(N(c["PuntoVenta"], 5));
            s.Append(N(c["Numero"], 20));
            s.Append(N(c["Numero"], 20));                          // numero hasta: uno por linea
            s.Append(N(docTipo, 2));
            s.Append(N(docTipo == 99 ? "0" : Convert.ToString(c["ReceptorDocNumero"]), 20));
            s.Append(A(nombre, 30));
            s.Append(I(c["ImporteTotal"]));
            s.Append(I(c["ImporteNoGravado"]));
            s.Append(I(0));                                       // percepcion a no categorizados
            s.Append(I(exento));
            s.Append(I(0));                                       // percepciones nacionales
            s.Append(I(0));                                       // percepciones IIBB
            s.Append(I(0));                                       // percepciones municipales
            s.Append(I(0));                                       // impuestos internos
            s.Append("PES");
            s.Append("0001000000");                               // tipo de cambio 1,000000
            s.Append(alic.Count == 0 ? "1" : alic.Count.ToString(CultureInfo.InvariantCulture));
            s.Append(alic.Count == 0 ? (exento > 0 ? "E" : "N") : "0");
            s.Append(I(c["ImporteTributos"]));
            s.Append("00000000");                                 // vencimiento de pago: solo servicios publicos
            return Largo(s.ToString(), 266);
        }

        private static IEnumerable<string> VentaAlicuotas(DataRow c, List<DataRow> alic)
        {
            string cab = N(c["TipoArca"], 3) + N(c["PuntoVenta"], 5) + N(c["Numero"], 20);
            if (alic.Count == 0)
            {
                yield return Largo(cab + I(0) + "0003" + I(0), 62);
                yield break;
            }
            foreach (DataRow a in alic)
                yield return Largo(cab + I(a["BaseImponible"]) + N(a["IdArcaIva"], 4) + I(a["Importe"]), 62);
        }

        private static string CompraCbte(DataRow c, List<DataRow> alic)
        {
            string letra = Convert.ToString(c["Letra"]);
            bool esA = letra == "A";
            decimal exento = D(c["ImporteExento"]);
            // En compras, los comprobantes B y C no informan alicuotas
            int cant = esA ? Math.Max(1, alic.Count) : 0;
            string codOper = esA && alic.Count == 0 ? (exento > 0 ? "E" : "N") : "0";
            var s = new StringBuilder();
            s.Append(F(c["Fecha"]));
            s.Append(N(c["TipoArca"], 3));
            s.Append(N(c["PuntoVenta"], 5));
            s.Append(N(c["Numero"], 20));
            s.Append(new string(' ', 16));                        // despacho de importacion
            s.Append("80");                                       // CUIT
            s.Append(N(Digitos(Convert.ToString(c["CuitProveedor"])), 20));
            s.Append(A(Convert.ToString(c["Proveedor"]), 30));
            s.Append(I(c["ImporteTotal"]));
            s.Append(I(c["ImporteNoGravado"]));
            s.Append(I(exento));
            s.Append(I(c["PercepcionIva"]));
            s.Append(I(0));                                       // otros impuestos nacionales
            s.Append(I(c["PercepcionIibb"]));
            s.Append(I(0));                                       // impuestos municipales
            s.Append(I(c["ImpuestosInternos"]));
            s.Append("PES");
            s.Append("0001000000");
            s.Append(cant.ToString(CultureInfo.InvariantCulture));
            s.Append(codOper);
            s.Append(I(c["CreditoFiscal"]));
            s.Append(I(c["OtrosTributos"]));
            s.Append(new string('0', 11));                        // CUIT corredor
            s.Append(new string(' ', 30));                        // denominacion corredor
            s.Append(I(0));                                       // IVA comision
            return Largo(s.ToString(), 325);
        }

        private static IEnumerable<string> CompraAlicuotas(DataRow c, List<DataRow> alic)
        {
            if (Convert.ToString(c["Letra"]) != "A") yield break;
            string cab = N(c["TipoArca"], 3) + N(c["PuntoVenta"], 5) + N(c["Numero"], 20) +
                         "80" + N(Digitos(Convert.ToString(c["CuitProveedor"])), 20);
            if (alic.Count == 0)
            {
                yield return Largo(cab + I(0) + "0003" + I(0), 84);
                yield break;
            }
            foreach (DataRow a in alic)
                yield return Largo(cab + I(a["BaseImponible"]) + N(a["IdArcaIva"], 4) + I(a["Importe"]), 84);
        }

        /* ---------------- Formato ---------------- */

        private static decimal D(object v) { return v == null || v == DBNull.Value ? 0m : Convert.ToDecimal(v); }

        // Importe: 15 posiciones, centavos sin separador, positivo
        private static string I(object v)
        {
            long centavos = (long)Math.Round(Math.Abs(D(v)) * 100m, MidpointRounding.AwayFromZero);
            return centavos.ToString(CultureInfo.InvariantCulture).PadLeft(15, '0');
        }

        private static string N(object v, int largo)
        {
            string t = v == null || v == DBNull.Value ? "0" : Digitos(Convert.ToString(v, CultureInfo.InvariantCulture));
            if (t == "") t = "0";
            return t.Length > largo ? t.Substring(t.Length - largo) : t.PadLeft(largo, '0');
        }

        private static string A(string v, int largo)
        {
            string t = (v ?? "").Replace("\r", " ").Replace("\n", " ").Trim();
            return t.Length > largo ? t.Substring(0, largo) : t.PadRight(largo, ' ');
        }

        private static string F(object v) { return Convert.ToDateTime(v).ToString("yyyyMMdd", CultureInfo.InvariantCulture); }

        private static string Digitos(string s) { return new string((s ?? "").Where(char.IsDigit).ToArray()); }

        // Red de seguridad: si una linea no tiene el largo exacto, mejor fallar que mandar un archivo roto
        private static string Largo(string linea, int esperado)
        {
            if (linea.Length != esperado)
                throw new InvalidOperationException("Línea de " + linea.Length + " caracteres en lugar de " + esperado + ".");
            return linea;
        }

        private DataSet Ejecutar(string sp, DateTime desde, DateTime hasta, bool? pruebas)
        {
            using (var cnn = new SqlConnection(_cnn))
            using (var cmd = new SqlCommand(sp, cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@Desde", SqlDbType.Date).Value = desde.Date;
                cmd.Parameters.Add("@Hasta", SqlDbType.Date).Value = hasta.Date;
                if (pruebas.HasValue) cmd.Parameters.Add("@IncluirPruebas", SqlDbType.Bit).Value = pruebas.Value;
                var ds = new DataSet();
                using (var da = new SqlDataAdapter(cmd)) { cnn.Open(); da.Fill(ds); }
                return ds;
            }
        }
    }
}
