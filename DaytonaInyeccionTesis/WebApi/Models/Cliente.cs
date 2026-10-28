using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class Cliente
    {
        private string connectionstring = Config.Conexion;

        public int Id { get; set; }
        public string Dni { get; set; }
        public string Nombre { get; set; }
        public string Apellido { get; set; }
        public string Telefono { get; set; }
        public string Mail { get; set; }
        public string Calle { get; set; }
        public string Numero { get; set; }
        public bool Activo { get; set; }

        // Marca de mecanico: habilita cuenta corriente y 10% de descuento fijo
        public bool EsMecanico { get; set; }

        // Limite de credito (script 82). Solo los mecanicos tienen cuenta
        // corriente. Vacio = sin limite. CambiarLimite lo manda la pantalla;
        // CambiarCredito lo decide el controlador: solo Dueño o Administrador.
        public decimal? LimiteCredito { get; set; }
        public bool CambiarLimite { get; set; }
        public bool CambiarCredito { get; set; }

        // Datos fiscales (script 92): deciden la letra del comprobante.
        // CondicionIva vacia en una edicion = no se tocan.
        public string CondicionIva { get; set; }
        public string Cuit { get; set; }
        public string RazonSocial { get; set; }

        // Listar todos
        public DataTable ListarTodos()
        {
            string sqlSentencia = "SP_Cliente_GetAll";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }

        // Listar uno por Id
        public DataTable ListarPorId()
        {
            string sqlSentencia = "SP_Cliente_GetById";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }

        // Insertar. Devuelve el Id generado, para poder dejar seleccionado
        // al cliente recien creado sin volver a buscarlo en la lista.
        public int Guardar()
        {
            string sqlSentencia = "SP_Cliente_I";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;

            // null se convierte a DBNull para que el campo opcional quede NULL en la base
            sqlCom.Parameters.Add("@Dni", SqlDbType.NVarChar).Value = (object)Dni ?? DBNull.Value;
            sqlCom.Parameters.Add("@Nombre", SqlDbType.NVarChar).Value = (object)Nombre ?? DBNull.Value;
            sqlCom.Parameters.Add("@Apellido", SqlDbType.NVarChar).Value = (object)Apellido ?? DBNull.Value;
            sqlCom.Parameters.Add("@Telefono", SqlDbType.NVarChar).Value = (object)Telefono ?? DBNull.Value;
            sqlCom.Parameters.Add("@Mail", SqlDbType.NVarChar).Value = (object)Mail ?? DBNull.Value;
            sqlCom.Parameters.Add("@Calle", SqlDbType.NVarChar).Value = (object)Calle ?? DBNull.Value;
            sqlCom.Parameters.Add("@Numero", SqlDbType.NVarChar).Value = (object)Numero ?? DBNull.Value;
            sqlCom.Parameters.Add("@EsMecanico", SqlDbType.Bit).Value = EsMecanico;
            AgregarCredito(sqlCom);
            AgregarFiscal(sqlCom);

            sqlCnn.Open();
            object resultado = sqlCom.ExecuteScalar();
            sqlCnn.Close();

            Id = resultado == null || resultado == DBNull.Value ? 0 : Convert.ToInt32(resultado);
            return Id;
        }

        // Actualizar
        public void Editar()
        {
            string sqlSentencia = "SP_Cliente_U";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;

            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;
            sqlCom.Parameters.Add("@Dni", SqlDbType.NVarChar).Value = (object)Dni ?? DBNull.Value;
            sqlCom.Parameters.Add("@Nombre", SqlDbType.NVarChar).Value = (object)Nombre ?? DBNull.Value;
            sqlCom.Parameters.Add("@Apellido", SqlDbType.NVarChar).Value = (object)Apellido ?? DBNull.Value;
            sqlCom.Parameters.Add("@Telefono", SqlDbType.NVarChar).Value = (object)Telefono ?? DBNull.Value;
            sqlCom.Parameters.Add("@Mail", SqlDbType.NVarChar).Value = (object)Mail ?? DBNull.Value;
            sqlCom.Parameters.Add("@Calle", SqlDbType.NVarChar).Value = (object)Calle ?? DBNull.Value;
            sqlCom.Parameters.Add("@Numero", SqlDbType.NVarChar).Value = (object)Numero ?? DBNull.Value;
            sqlCom.Parameters.Add("@EsMecanico", SqlDbType.Bit).Value = EsMecanico;
            AgregarCredito(sqlCom);
            AgregarFiscal(sqlCom);

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        private void AgregarFiscal(SqlCommand sqlCom)
        {
            sqlCom.Parameters.Add("@CondicionIva", SqlDbType.VarChar, 30).Value =
                string.IsNullOrWhiteSpace(CondicionIva) ? (object)DBNull.Value : CondicionIva.Trim();
            sqlCom.Parameters.Add("@Cuit", SqlDbType.VarChar, 20).Value =
                string.IsNullOrWhiteSpace(Cuit) ? (object)DBNull.Value : Cuit.Trim();
            sqlCom.Parameters.Add("@RazonSocial", SqlDbType.NVarChar, 120).Value =
                string.IsNullOrWhiteSpace(RazonSocial) ? (object)DBNull.Value : RazonSocial.Trim();
        }

        private void AgregarCredito(SqlCommand sqlCom)
        {
            SqlParameter pLim = sqlCom.Parameters.Add("@LimiteCredito", SqlDbType.Decimal);
            pLim.Precision = 12; pLim.Scale = 2;
            pLim.Value = LimiteCredito.HasValue ? (object)LimiteCredito.Value : DBNull.Value;
            sqlCom.Parameters.Add("@CambiarCredito", SqlDbType.Bit).Value = CambiarCredito;
        }

        // Situacion de credito: saldo, limite, disponible, deuda mas vieja
        // y las ultimas autorizaciones para pasar el limite
        public DataSet Credito()
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand("SP_Cliente_Credito", cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@IdCliente", SqlDbType.Int).Value = Id;
                DataSet ds = new DataSet();
                using (SqlDataAdapter da = new SqlDataAdapter(cmd))
                {
                    cnn.Open();
                    da.Fill(ds);
                }
                return ds;
            }
        }

        // Baja logica: marca el cliente como inactivo (no borra)
        public void Eliminar()
        {
            string sqlSentencia = "SP_Cliente_D";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Reactiva un cliente dado de baja
        public void Activar()
        {
            string sqlSentencia = "SP_Cliente_Activar";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }
    }
}