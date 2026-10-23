using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    /* Actualizacion de listas de precios desde el sistema (script 75).
       El navegador lee el Excel y manda las filas en tandas; aca se
       cargan en la tabla de paso con SqlBulkCopy (sin BULK INSERT, que
       necesita un archivo en el servidor y no existe en Azure). */
    public class Importacion
    {
        private string connectionstring = Config.Conexion;
        private const int Columnas = 20;   // StgImportacion: Col1..Col20

        public DataTable Perfiles()
        {
            return Consultar("SP_Importacion_Perfiles", null, 30).Tables[0];
        }

        // Carga una tanda de filas. La primera tanda vacia la tabla de paso.
        public int CargarFilas(List<List<string>> filas, bool primeraTanda)
        {
            DataTable t = new DataTable();
            for (int c = 1; c <= Columnas; c++) t.Columns.Add("Col" + c, typeof(string));

            foreach (List<string> f in filas)
            {
                DataRow r = t.NewRow();
                for (int c = 0; c < Columnas; c++)
                {
                    string v = (f != null && c < f.Count) ? f[c] : null;
                    if (v != null)
                    {
                        v = v.Trim();
                        if (v.Length > 300) v = v.Substring(0, 300);
                        if (v.Length == 0) v = null;
                    }
                    r[c] = (object)v ?? DBNull.Value;
                }
                t.Rows.Add(r);
            }

            using (SqlConnection cnn = new SqlConnection(connectionstring))
            {
                cnn.Open();
                if (primeraTanda)
                {
                    using (SqlCommand cmd = new SqlCommand("TRUNCATE TABLE StgImportacion", cnn))
                        cmd.ExecuteNonQuery();
                }
                using (SqlBulkCopy bulk = new SqlBulkCopy(cnn))
                {
                    bulk.DestinationTableName = "StgImportacion";
                    bulk.BulkCopyTimeout = 300;
                    for (int c = 1; c <= Columnas; c++) bulk.ColumnMappings.Add("Col" + c, "Col" + c);
                    bulk.WriteToServer(t);
                }
                using (SqlCommand cnt = new SqlCommand("SELECT COUNT(*) FROM StgImportacion", cnn))
                    return Convert.ToInt32(cnt.ExecuteScalar());
            }
        }

        public DataSet Comparar(int idProveedor)
        {
            return Consultar("SP_Importacion_Comparar", c =>
                c.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = idProveedor, 600);
        }

        public DataSet Procesar(int idProveedor, DateTime fechaLista)
        {
            DataSet ds = Consultar("SP_Importacion_Procesar", c =>
            {
                c.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = idProveedor;
                c.Parameters.Add("@FechaLista", SqlDbType.Date).Value = fechaLista.Date;
            }, 900);

            // El texto de busqueda de lo que se actualizo se rearma enseguida
            Consultar("SP_Busqueda_Reprocesar", c =>
                c.Parameters.Add("@SoloNuevos", SqlDbType.Bit).Value = true, 900);
            return ds;
        }

        private DataSet Consultar(string sp, Action<SqlCommand> parametros, int timeout)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand(sp, cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.CommandTimeout = timeout;
                if (parametros != null) parametros(cmd);
                DataSet ds = new DataSet();
                new SqlDataAdapter(cmd).Fill(ds);
                return ds;
            }
        }
    }
}
