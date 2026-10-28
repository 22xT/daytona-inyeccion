using System.Linq;

namespace WebApi.Models
{
    /* Telefono argentino para WhatsApp (28/10, pruebas E1/E4).
       Lo mismo que Pages/telefono.js: se acepta 351 7585566, 0351 15 758-5566,
       +54 9 351 7585566... y se guarda "351 7585566" (codigo de area sin 0,
       un espacio, numero sin 15: 10 digitos en total). */
    public static class Telefono
    {
        private static readonly string[] Area3 = {
            "220", "221", "223", "230", "236", "237", "249", "260", "261", "263", "264", "266",
            "280", "291", "294", "297", "298", "299", "336", "341", "342", "343", "345", "348",
            "351", "353", "358", "362", "364", "370", "376", "379", "380", "381", "383", "385",
            "387", "388" };

        // Los 10 digitos, o null si no es un numero valido
        public static string Normalizar(string texto)
        {
            if (string.IsNullOrWhiteSpace(texto)) return null;
            string d = new string(texto.Where(char.IsDigit).ToArray());
            if (d.StartsWith("549") && d.Length == 13) d = d.Substring(3);
            else if (d.StartsWith("54") && d.Length == 12) d = d.Substring(2);
            if (d.StartsWith("0")) d = d.Substring(1);
            if (d.Length == 12)
            {
                for (int a = 2; a <= 4; a++)
                    if (d.Substring(a, 2) == "15") { d = d.Substring(0, a) + d.Substring(a + 2); break; }
            }
            if (d.Length != 10 || d[0] == '0' || d.All(c => c == d[0])) return null;
            return d;
        }

        // "3517585566" -> "351 7585566"; si no es valido, null
        public static string Formatear(string texto)
        {
            string d = Normalizar(texto);
            if (d == null) return null;
            int a = d.StartsWith("11") ? 2 : (Area3.Contains(d.Substring(0, 3)) ? 3 : 4);
            return d.Substring(0, a) + " " + d.Substring(a);
        }

        public const string Error = "El teléfono no es válido: va el código de área y el número, por ejemplo 351 7585566.";
    }
}
