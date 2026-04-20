import asyncio
from supabase import acreate_client
import paho.mqtt.client as mqtt
import json
import os
import time
from datetime import datetime, timezone, timedelta

SUPABASE_URL = "https://czxyfzxjwzaykwoxyjah.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN6eHlmenhqd3pheWt3b3h5amFoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA0MjgzMDAsImV4cCI6MjA2NjAwNDMwMH0.w3kzZcb1Rix5kaxRUhy2dCVkQHvsT_TYDhtg_3O1Q0A"

MAQUINA_ID = "9991"
ARCHIVO_ESTADO = "/home/recomputer/estado_semaforo.json"
TIEMPO_RECONEXION = 600  # 10 minutos

BROKER = "localhost"
PORT = 1883
TOPIC = "maquina/9991/estado"

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
client = mqtt.Client(client_id="", protocol=mqtt.MQTTv311)

def on_connect(client, userdata, flags, rc):
    print("Conectado a MQTT correctamente" if rc == 0 else f"Error conectando MQTT: {rc}")

def on_disconnect(client, userdata, rc):
    print("Desconectado de MQTT. Reconectando...")
    while True:
        try:
            client.reconnect()
            break
        except Exception as e:
            print("Error reconectando MQTT, retry en 5s:", e)
            time.sleep(5)

client.on_connect = on_connect
client.on_disconnect = on_disconnect
client.connect(BROKER, PORT, 60)
client.loop_start()

def publish_mqtt(estado):
    """Publica JSON con maquina y estado al topic MQTT.
    Node-RED espera: {\"maquina\": \"9991\", \"estado\": \"Verde\"}
    """
    try:
        payload = json.dumps({"maquina": MAQUINA_ID, "estado": estado})
        client.publish(TOPIC, payload)
        print(f"Enviado a MQTT: {payload}")
    except Exception as e:
        print("Error publicando MQTT:", e)

async def publish_mqtt_async(estado):
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(None, publish_mqtt, estado)

# =======================
# ARCHIVO LOCAL (BACKUP)
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
        print("Error guardando estado local:", e)

def leer_estado_local():
    if not os.path.exists(ARCHIVO_ESTADO):
        return None
    try:
        with open(ARCHIVO_ESTADO, "r") as f:
            return json.load(f)
    except Exception:
        return None

async def enviar_estado_local_si_existe():
    data = leer_estado_local()
    if data:
        print("Estado local encontrado:", data["estado"])
        await publish_mqtt_async(data["estado"])

# =======================
# SUPABASE — CONSULTA ESTADO ACTUAL
# =======================
async def enviar_estado_inicial_supabase(supabase):
    """
    Consulta el estado del semáforo para el turno actual del día de hoy.
    La tabla semaforo_maquina tiene UNA fila por (id_maquina, turno, fecha_periodo).
    Se filtra por turno activo y fecha de hoy para obtener el registro correcto.
    Si no existe registro para el turno actual, busca el más reciente del día.
    """
    turno = get_turno_actual()
    fecha_hoy = get_fecha_hoy_ec()

    print(f"Consultando semáforo para máquina={MAQUINA_ID}, turno={turno}, fecha={fecha_hoy}")

    try:
        # Intento 1: Registro exacto del turno actual + hoy
        resp = await supabase.table("semaforo_maquina") \
            .select("estado, turno, fecha_periodo") \
            .eq("id_maquina", MAQUINA_ID) \
            .eq("turno", turno) \
            .eq("fecha_periodo", fecha_hoy) \
            .limit(1) \
            .execute()

        if resp.data:
            estado = resp.data[0]["estado"]
            print(f"Estado actual ({turno}/{fecha_hoy}): {estado}")
        else:
            # Intento 2: El más reciente del día (cualquier turno)
            print(f"No hay registro para turno {turno} hoy. Buscando el más reciente...")
            resp2 = await supabase.table("semaforo_maquina") \
                .select("estado, turno, fecha_actualizacion") \
                .eq("id_maquina", MAQUINA_ID) \
                .eq("fecha_periodo", fecha_hoy) \
                .order("fecha_actualizacion", desc=True) \
                .limit(1) \
                .execute()

            if resp2.data:
                estado = resp2.data[0]["estado"]
                print(f"Estado más reciente del día: {estado} (turno={resp2.data[0]['turno']})")
            else:
                print("Sin registros para hoy. Usando Verde por defecto.")
                estado = "Verde"

        guardar_estado_local(estado)
        await publish_mqtt_async(estado)

    except Exception as e:
        print("No se pudo leer estado inicial de Supabase:", e)
        await enviar_estado_local_si_existe()

# =======================
# MAIN + REALTIME
# =======================
async def main():
    while True:
        try:
            # 1️⃣ Enviar respaldo local inmediato mientras conecta
            await enviar_estado_local_si_existe()

            # 2️⃣ Conectar Supabase
            supabase = await acreate_client(SUPABASE_URL, SUPABASE_KEY)
            print("Conectado a Supabase Realtime")

            # 3️⃣ Leer estado real UNA VEZ (turno actual)
            await enviar_estado_inicial_supabase(supabase)

            # 4️⃣ Suscripción Realtime a cambios en semaforo_maquina
            realtime = supabase.realtime
            channel = realtime.channel("public:semaforo_maquina:9991")

            def handle_changes(payload):
                """
                Recibe el payload de Supabase Realtime cuando hay un INSERT o UPDATE
                en semaforo_maquina. Solo reacciona si corresponde a la máquina 9991
                y al turno activo en ese momento.
                """
                try:
                    record = payload["data"]["record"]
                    if record.get("id_maquina") != MAQUINA_ID:
                        return

                    turno_actual = get_turno_actual()
                    turno_record = record.get("turno", "")
                    estado = record.get("estado")

                    print(f"Realtime — Cambio recibido: turno={turno_record}, estado={estado}")

                    # Solo publicar si el cambio es del turno activo (o si no hay turno en el record)
                    if not turno_record or turno_record == turno_actual:
                        guardar_estado_local(estado)
                        asyncio.get_event_loop().create_task(
                            publish_mqtt_async(estado)
                        )
                    else:
                        print(f"Ignorado: cambio de turno '{turno_record}' ≠ turno actual '{turno_actual}'")

                except Exception as e:
                    print("Error procesando payload Realtime:", e)

            await channel.on_postgres_changes(
                event="*",
                schema="public",
                table="semaforo_maquina",
                filter=f"id_maquina=eq.{MAQUINA_ID}",
                callback=handle_changes
            ).subscribe()

            print(f"Escuchando cambios semáforo máquina {MAQUINA_ID} (máx 10 min)...")

            # ⏱️ Reconexión preventiva cada 10 minutos
            await asyncio.sleep(TIEMPO_RECONEXION)

            print("Reiniciando conexión Supabase por timeout preventivo (10 min)")

            # 🔄 Cierre limpio
            try:
                await channel.unsubscribe()
            except Exception:
                pass

            try:
                await supabase.realtime.disconnect()
            except Exception:
                pass

        except Exception as e:
            print("Error Supabase, reintentando en 5s:", e)
            await asyncio.sleep(5)

asyncio.run(main())
