using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    /* Inventario fisico con conteo ciego (script 79).
       Mientras el conteo esta abierto, la base no devuelve el stock
       del sistema: recien aparece al revisar las diferencias. */
    public class Inventario
    {
        private string connectionstring = Config.Conexion;

        public DataTable Iniciar(int? idRubro, int idUsuario, string observacion)
        {
            return Ejecutar("SP_Inventario_Iniciar", c =>
            {
                c.Parameters.Add("@IdRubro", SqlDbType.Int).Value = idRubro.HasValue && idRubro.Value > 0 ? (object)idRubro.Value : DBNull.Value;
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
                c.Parameters.Add("@Observacion", SqlDbType.NVarChar, 250).Value = (object)observacion ?? DBNull.Value;
            }).Tables[0];
        }

        public DataSet Get(int? id)
        {
            return Ejecutar("SP_Inventario_Get", c =>
                c.Parameters.Add("@Id", SqlDbType.Int).Value = id.HasValue && id.Value > 0 ? (object)id.Value : DBNull.Value);
        }

        public DataTable Contar(int idConteo, int idRepuesto, int? contado, int idUsuario)
        {
            return Ejecutar("SP_Inventario_Contar", c =>
            {
                c.Parameters.Add("@IdConteo", SqlDbType.Int).Value = idConteo;
                c.Parameters.Add("@IdRepuesto", SqlDbType.Int).Value = idRepuesto;
                c.Parameters.Add("@Contado", SqlDbType.Int).Value = contado.HasValue ? (object)contado.Value : DBNull.Value;
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            }).Tables[0];
        }

        public DataSet Diferencias(int idConteo)
        {
            return Ejecutar("SP_Inventario_Diferencias", c =>
                c.Parameters.Add("@IdConteo", SqlDbType.Int).Value = idConteo);
        }

        public void Motivo(int idRenglon, string motivo)
        {
            Ejecutar("SP_Inventario_Motivo", c =>
            {
                c.Parameters.Add("@IdRenglon", SqlDbType.Int).Value = idRenglon;
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 200).Value = (object)motivo ?? DBNull.Value;
            });
        }

        public DataTable Cerrar(int idConteo, int idUsuario, string motivoGeneral)
        {
            DataSet ds = Ejecutar("SP_Inventario_Cerrar", c =>
            {
                c.Parameters.Add("@IdConteo", SqlDbType.Int).Value = idConteo;
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
                c.Parameters.Add("@MotivoGeneral", SqlDbType.NVarChar, 200).Value = (object)motivoGeneral ?? DBNull.Value;
            });
            return ds.Tables.Count > 0 ? ds.Tables[ds.Tables.Count - 1] : null;
        }

        public void Anular(int idConteo, int idUsuario)
        {
            Ejecutar("SP_Inventario_Anular", c =>
            {
                c.Parameters.Add("@IdConteo", SqlDbType.Int).Value = idConteo;
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        public DataTable Lista()
        {
            return Ejecutar("SP_Inventario_Lista", null).Tables[0];
        }

        private DataSet Ejecutar(string sp, Action<SqlCommand> parametros)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand(sp, cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.CommandTimeout = 300;
                if (parametros != null) parametros(cmd);
                DataSet ds = new DataSet();
                new SqlDataAdapter(cmd).Fill(ds);
                return ds;
            }
        }
    }
}
