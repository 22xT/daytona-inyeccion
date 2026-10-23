/* =================================================================
   config.js — configuracion del frontend

   UNICO lugar donde vive la direccion del backend. Antes estaba
   escrita adentro de cada pantalla, asi que cambiar de servidor
   significaba editar dieciocho archivos y era cuestion de tiempo
   que alguno quedara apuntando al lugar equivocado.

   SE ELIGE SOLA, sin tocar nada al publicar:
     - En la PC (localhost o abriendo el archivo): la API local,
       http://localhost:52954/api/
     - Publicado en Azure: las pantallas estan en la carpeta /app del
       mismo sitio que la API, asi que la API esta en el mismo
       origen: https://<sitio>/api/

   Este archivo tiene que cargarse ANTES que auth.js y que el script
   de cada pantalla.
   ================================================================= */

var API_BASE = (location.protocol === "file:" || location.hostname === "localhost" || location.hostname === "127.0.0.1")
  ? "http://localhost:52954/api/"
  : location.origin + "/api/";

// Por si alguna pantalla necesita la raiz sin /api/
var APP_BASE = API_BASE.replace(/\/api\/?$/, "/");
