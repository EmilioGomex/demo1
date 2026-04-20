import asyncio
from supabase import acreate_client
import paho.mqtt.client as mqtt
import json
import os
import time
import logging
from datetime import datetime, timezone, timedelta

# Configuración de Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Configuración
SUPABASE_URL = "https://czxyfzxjwzaykwoxyjah.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN6eHlmenhqd3pheWt3b3h5amFoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA0MjgzMDAsImV4cCI6MjA2NjAwNDMwMH0.w3kzZcb1Rix5kaxRUhy2dCVkQHvsT_TYDhtg_3O1Q0A"

MAQUINA_ID = "9991"
ARCHIVO_ESTADO = "/home/recomputer/estado_semaforo.json"
TIEMPO_RECONEXION = 600  # 10 minutos (timeout preventivo)

BROKER = "localhost"
PORT = 1883
TOPIC = f"maquina/{MAQUINA_ID}/estado"

# =======================
# UTILIDADES DE TIEMPO (Ecuador UTC-5)
# =======================
TZ_EC = timezone(timedelta(hours=-5))

def get_turno_actual():
    """Retorna el turno activo según la hora Ecuador."""
    hora = datetime.now(TZ_EC).hour
    if 6 <= hora < 14:
        return "Mañana"
    elif 14 <= hora < 22:
        return "Tarde"
    else:
        return "Noche"

def get_fecha_hoy_ec():
    """Retorna la fecha de hoy en Ecuador como string YYYY-MM-DD."""
    return datetime.now(TZ_EC).strftime("%Y-%m-%d")

# =======================
# MQTT
# =======================
mqtt_client = mqtt.Client(client_id=f"rpi_semaforo_{MAQUINA_ID}", protocol=mqtt.MQTTv311)

def on_connect(client, userdata, flags, rc):
    if rc == 0:
        logger.info("Conectado a MQTT Broker local")
    else:
        logger.error(f"Fallo conexión MQTT, código: {rc}")

def on_disconnect(client, userdata, rc):
    if rc != 0:
        logger.warning("Desconexión inesperada de MQTT. La librería paho reintentará automáticamente.")

mqtt_client.on_connect = on_connect
mqtt_client.on_disconnect = on_disconnect

def connect_mqtt():
    try:
        mqtt_client.connect(BROKER, PORT, 60)
        mqtt_client.loop_start()
    except Exception as e:
        logger.error(f"No se pudo iniciar MQTT: {e}")

def publish_mqtt(estado):
    """Publica JSON al topic MQTT."""
    try:
        payload = json.dumps({
            "maquina": MAQUINA_ID, 
            "estado": estado,
            "timestamp": datetime.now(TZ_EC).isoformat()
        })
        mqtt_client.publish(TOPIC, payload, qos=1, retain=True)
        logger.info(f">>> MQTT Publicado: {estado}")
    except Exception as e:
        logger.error(f"Error publicando MQTT: {e}")

# =======================
# ARCHIVO LOCAL (PERSISTENCIA)
# =======================
def guardar_estado_local(estado):
    try:
        with open(ARCHIVO_ESTADO, "w") as f:
            json.dump({
                "maquina": MAQUINA_ID,
                "estado": estado,
                "timestamp": time.time()
            }, f)
    except Exception as e:
        logger.error(f"Error guardando estado local: {e}")

def leer_estado_local():
    if not os.path.exists(ARCHIVO_ESTADO):
        return None
    try:
        with open(ARCHIVO_ESTADO, "r") as f:
            return json.load(f)
    except Exception:
        return None

# =======================
# SUPABASE LÓGICA
# =======================
async def consultar_y_publicar_estado(supabase):
    """Consulta el estado actual en Supabase y lo sincroniza."""
    turno = get_turno_actual()
    fecha_hoy = get_fecha_hoy_ec()

    try:
        # Intento 1: Registro exacto del turno actual
        resp = await supabase.table("semaforo_maquina") \
            .select("estado") \
            .eq("id_maquina", MAQUINA_ID) \
            .eq("turno", turno) \
            .eq("fecha_periodo", fecha_hoy) \
            .limit(1) \
            .execute()

        if resp.data:
            estado = resp.data[0]["estado"]
            logger.info(f"Estado Supabase (Turno Actual): {estado}")
        else:
            # Intento 2: Registro más reciente de hoy
            resp2 = await supabase.table("semaforo_maquina") \
                .select("estado") \
                .eq("id_maquina", MAQUINA_ID) \
                .eq("fecha_periodo", fecha_hoy) \
                .order("fecha_actualizacion", desc=True) \
                .limit(1) \
                .execute()
            
            estado = resp2.data[0]["estado"] if resp2.data else "Verde"
            logger.info(f"Estado Supabase (Más reciente hoy): {estado}")

        guardar_estado_local(estado)
        publish_mqtt(estado)

    except Exception as e:
        logger.error(f"Error consultando Supabase: {e}")
        # Si falla, usamos el respaldo local
        local = leer_estado_local()
        if local:
            logger.info(f"Usando respaldo local: {local['estado']}")
            publish_mqtt(local['estado'])

async def main():
    connect_mqtt()
    
    while True:
        try:
            # 1. Iniciar cliente Supabase
            async with acreate_client(SUPABASE_URL, SUPABASE_KEY) as supabase:
                logger.info("--- Nueva sesión Supabase iniciada ---")
                
                # 2. Sincronización inicial
                await consultar_y_publicar_estado(supabase)

                # 3. Configurar Realtime
                loop = asyncio.get_running_loop()
                
                def on_change(payload):
                    """Callback para cambios en tiempo real."""
                    try:
                        # Manejar INSERT, UPDATE o DELETE
                        data = payload.get("data", {})
                        record = data.get("record") or data.get("old_record")
                        
                        if not record: return

                        estado = record.get("estado")
                        turno_rec = record.get("turno")
                        turno_act = get_turno_actual()

                        # Solo reaccionar si es el turno actual
                        if turno_rec == turno_act:
                            logger.info(f"EVENTO REALTIME: {estado}")
                            guardar_estado_local(estado)
                            # Publicar de forma no bloqueante
                            loop.call_soon_threadsafe(publish_mqtt, estado)
                    except Exception as e:
                        logger.error(f"Error procesando realtime: {e}")

                channel = supabase.channel(f"semaforo_{MAQUINA_ID}")
                await channel.on_postgres_changes(
                    event="*",
                    schema="public",
                    table="semaforo_maquina",
                    filter=f"id_maquina=eq.{MAQUINA_ID}",
                    callback=on_change
                ).subscribe()

                logger.info("Escuchando cambios en tiempo real...")
                
                # Esperar hasta el timeout preventivo o hasta que falle la conexión
                await asyncio.sleep(TIEMPO_RECONEXION)
                
                logger.info("Reiniciando sesión por seguridad...")
                await channel.unsubscribe()

        except Exception as e:
            logger.error(f"Error en loop principal: {e}. Reintentando en 10s...")
            await asyncio.sleep(10)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Script detenido por el usuario.")
    finally:
        mqtt_client.loop_stop()
        mqtt_client.disconnect()
