using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    // Lo que se declara de un medio electronico al cerrar (script 94)
    public class MedioDeclarado
    {
        public int IdMedioPago { get; set; }
        public decimal Declarado { get; set; }
    }

    // Apertura, arqueo ciego y cierre de la caja fisica (scripts 42 y 94)
    public class SesionCaja
    {
        private string connectionstring = Config.Conexion;

        private static object N(object v) { return v ?? DBNull.Value; }

        // verTeorico = false: quien cierra a ciegas no ve lo que deberia haber
        public DataTable Actual(bool verTeorico)
        {
            return Consultar("SP_SesionCaja_Actual", c =>
            {
                c.Parameters.Add("@VerTeorico", SqlDbType.Bit).Value = verTeorico;
            }).Tables[0];
        }

        public DataTable Abrir(decimal saldoInicial, string motivo, int idUsuario)
        {
            return Consultar("SP_SesionCaja_Abrir", c =>
            {
                c.Parameters.Add("@SaldoInicial", SqlDbType.Decimal).Value = saldoInicial;
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(motivo);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            }).Tables[0];
        }

        // Devuelve el cierre y el arqueo por medio
        public DataSet Cerrar(decimal efectivoContado, string motivo, int idUsuario, List<MedioDeclarado> medios)
        {
            DataTable tvp = new DataTable();
            tvp.Columns.Add("IdMedioPago", typeof(int));
            tvp.Columns.Add("Declarado", typeof(decimal));
            if (medios != null)
                foreach (MedioDeclarado m in medios)
                    tvp.Rows.Add(m.IdMedioPago, m.Declarado);

            return Consultar("SP_SesionCaja_Cerrar", c =>
            {
                c.Parameters.Add("@EfectivoContado", SqlDbType.Decimal).Value = efectivoContado;
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(motivo);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
                SqlParameter p = c.Parameters.AddWithValue("@Medios", tvp);
                p.SqlDbType = SqlDbType.Structured;
                p.TypeName = "dbo.ArqueoMedioType";
            });
        }

        public void Explicar(int idSesion, string motivo, int idUsuario)
        {
            Consultar("SP_SesionCaja_Explicar", c =>
            {
                c.Parameters.Add("@IdSesion", SqlDbType.Int).Value = idSesion;
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(motivo);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        public void Aprobar(int idSesion, string comentario, int idUsuario)
        {
            Consultar("SP_SesionCaja_Aprobar", c =>
            {
                c.Parameters.Add("@IdSesion", SqlDbType.Int).Value = idSesion;
                c.Parameters.Add("@Comentario", SqlDbType.NVarChar, 250).Value = N(comentario);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        // Cabecera, efectivo por concepto, medios, ventas, cobrado por medio y comprobantes
        public DataSet Resumen(int idSesion)
        {
            return Consultar("SP_SesionCaja_Resumen", c =>
            {
                c.Parameters.Add("@IdSesion", SqlDbType.Int).Value = idSesion;
            });
        }

        // Medios electronicos que se declaran al cerrar (sin importes)
        public DataTable MediosArqueo()
        {
            return Consultar("SP_SesionCaja_MediosArqueo", c => { }).Tables[0];
        }

        public DataTable Historial(DateTime? desde, DateTime? hasta)
        {
            return Consultar("SP_SesionCaja_Historial", c =>
            {
                c.Parameters.Add("@Desde", SqlDbType.Date).Value = N(desde);
                c.Parameters.Add("@Hasta", SqlDbType.Date).Value = N(hasta);
            }).Tables[0];
        }

        public DataTable ResumenDiferencias(DateTime? desde, DateTime? hasta)
        {
            return Consultar("SP_SesionCaja_ResumenDiferencias", c =>
            {
                c.Parameters.Add("@Desde", SqlDbType.Date).Value = N(desde);
                c.Parameters.Add("@Hasta", SqlDbType.Date).Value = N(hasta);
            }).Tables[0];
        }

        private DataSet Consultar(string sp, Action<SqlCommand> parametros)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand(sp, cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                parametros(cmd);
                DataSet ds = new DataSet();
                using (SqlDataAdapter da = new SqlDataAdapter(cmd)) { da.Fill(ds); }
                if (ds.Tables.Count == 0) ds.Tables.Add(new DataTable());
                return ds;
            }
        }
    }
}
