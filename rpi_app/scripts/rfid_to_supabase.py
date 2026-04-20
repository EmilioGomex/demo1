#!/usr/bin/env python3
"""
rfid_to_supabase.py
Lee tarjetas RFID (por input o puerto serial) y registra en Supabase REST.
Opcional: publica en un broker MQTT.

Requisitos:
pip install requests python-dotenv pyserial paho-mqtt

Uso:
export SUPABASE_URL="https://tu-proyecto.supabase.co/rest/v1/lecturas_rfid"
export SUPABASE_KEY="tu_service_role_o_anon_key"
# O crea un archivo .env con esas variables (ver ejemplo abajo)

python rfid_to_supabase.py --mode input
python rfid_to_supabase.py --mode serial --serial-device /dev/ttyUSB0 --baud 9600
python rfid_to_supabase.py --mode input --mqtt --mqtt-broker localhost --mqtt-topic rfid/access
"""

import os
import sys
import time
import json
import argparse
import logging
import signal
from datetime import datetime
from typing import Optional

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from dotenv import load_dotenv

# Intentamos importar opcionales
try:
    import serial  # pyserial
except Exception:
    serial = None

try:
    import paho.mqtt.client as mqtt  # paho-mqtt
except Exception:
    mqtt = None

# Cargar .env
load_dotenv()

# ---------- Configuración ----------
SUPABASE_URL = os.getenv("SUPABASE_URL")  # ej: https://xxx.supabase.co/rest/v1/lecturas_rfid
SUPABASE_KEY = os.getenv("SUPABASE_KEY")  # service_role o anon key (mejor: backend en service_role)
DEFAULT_TIMEOUT = float(os.getenv("HTTP_TIMEOUT", "10"))  # segundos
MAX_RETRIES = int(os.getenv("HTTP_MAX_RETRIES", "5"))
RETRY_BACKOFF_FACTOR = float(os.getenv("HTTP_BACKOFF_FACTOR", "0.5"))
# -----------------------------------

if not SUPABASE_URL or not SUPABASE_KEY:
    print("ERROR: Debes configurar SUPABASE_URL y SUPABASE_KEY en variables de entorno o .env.")
    sys.exit(1)

# Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
log = logging.getLogger("rfid_supabase")

# Create requests session with retries
session = requests.Session()
retry_strategy = Retry(
    total=MAX_RETRIES,
    status_forcelist=[429, 500, 502, 503, 504],
    method_whitelist=["POST", "GET", "PUT", "PATCH", "DELETE"],
    backoff_factor=RETRY_BACKOFF_FACTOR,
    raise_on_status=False,
)
adapter = HTTPAdapter(max_retries=retry_strategy)
session.mount("https://", adapter)
session.mount("http://", adapter)

headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    # Si tu tabla requiere preferencia de retorno, podrías usar: "Prefer": "return=representation"
}

# Graceful stop
running = True


def handle_sigint(signum, frame):
    global running
    log.info("Recibida señal de terminación, cerrando...")
    running = False


signal.signal(signal.SIGINT, handle_sigint)
signal.signal(signal.SIGTERM, handle_sigint)


# MQTT helper
class MQTTClient:
    def __init__(self, broker: str, port: int = 1883, client_id: Optional[str] = None):
        if mqtt is None:
            raise RuntimeError("paho-mqtt no está instalado. Instálalo con `pip install paho-mqtt`")
        self.broker = broker
        self.port = port
        self.client = mqtt.Client(client_id or f"rfid-client-{int(time.time())}")
        self.connected = False
        # Callbacks
        self.client.on_connect = self._on_connect
        self.client.on_disconnect = self._on_disconnect

    def _on_connect(self, client, userdata, flags, rc):
        if rc == 0:
            self.connected = True
            log.info(f"Conectado a MQTT broker {self.broker}:{self.port}")
        else:
            log.warning(f"MQTT conexión fallida, rc={rc}")

    def _on_disconnect(self, client, userdata, rc):
        self.connected = False
        log.info("Desconectado de MQTT broker")

    def connect(self):
        try:
            self.client.connect(self.broker, self.port, keepalive=60)
            self.client.loop_start()
            # esperar hasta conectarse (timeout 5s)
            t0 = time.time()
            while not self.connected and time.time() - t0 < 5:
                time.sleep(0.1)
        except Exception as e:
            log.exception("Error conectando a MQTT broker: %s", e)

    def publish(self, topic: str, payload: str, qos: int = 0, retain: bool = False):
        if not self.connected:
            log.debug("MQTT no conectado, intentando conectar...")
            try:
                self.connect()
            except Exception:
                log.debug("No se pudo conectar a MQTT, omitiendo publish")
                return
        try:
            self.client.publish(topic, payload, qos=qos, retain=retain)
            log.debug("Publicado en MQTT %s: %s", topic, payload)
        except Exception:
            log.exception("Error publicando en MQTT")

    def disconnect(self):
        try:
            self.client.loop_stop()
            self.client.disconnect()
        except Exception:
            pass


def insert_supabase_record(card_id: str) -> bool:
    """
    Inserta un registro en la tabla Supabase.
    Ajusta el payload según la estructura de tu tabla.
    Devuelve True si fue insertado correctamente.
    """
    url = SUPABASE_URL
    # payload por defecto - ajusta campos a tu tabla
    payload = {
        "id_operador": str(card_id),
        "procesado": False,
        "fecha_lectura": datetime.utcnow().isoformat()  # si tu tabla tiene timestamp
    }

    try:
        log.debug("Enviando payload a Supabase: %s", payload)
        # Si quieres que Supabase devuelva la fila creada, agrega header Prefer
        response = session.post(url, headers={**headers, "Prefer": "return=representation"}, json=payload, timeout=DEFAULT_TIMEOUT)
    except requests.exceptions.RequestException as e:
        log.error("Error de conexión a Supabase al insertar %s: %s", card_id, e)
        return False

    if response.status_code in (200, 201):
        try:
            # Supabase normalmente devuelve la fila insertada si Prefer=return=representation
            data = response.json()
            log.info("Tarjeta %s registrada en Supabase. Respuesta: %s", card_id, data)
        except Exception:
            log.info("Tarjeta %s registrada en Supabase. Código: %s", card_id, response.status_code)
        return True
    else:
        # Mostrar texto de error (cuidado con exponer keys en logs si hay info sensible)
        log.error("Fallo al registrar %s. HTTP %s - %s", card_id, response.status_code, response.text)
        return False


def run_input_loop(mqtt_client: Optional[MQTTClient], mqtt_topic: Optional[str]):
    """
    Bucle principal leyendo desde input() (lector como teclado).
    """
    global running
    log.info("Modo input: espera tarjetas (presiona Ctrl+C para salir).")
    while running:
        try:
            card_id = input().strip()
        except EOFError:
            # por ejemplo cierre del stdin
            log.info("EOF en stdin, saliendo.")
            break
        except KeyboardInterrupt:
            log.info("KeyboardInterrupt recibido.")
            break

        if not card_id:
            continue

        log.info("Tarjeta detectada: %s", card_id)

        # Publicar a MQTT si está configurado
        if mqtt_client and mqtt_topic:
            try:
                mqtt_client.publish(mqtt_topic, card_id)
            except Exception:
                log.exception("Error publicando a MQTT")

        # Intentar insertar en Supabase (reintentos ya gestionados por session)
        ok = insert_supabase_record(card_id)
        if not ok:
            log.warning("Registro fallido para %s — se omitirá o reintentarás manualmente.", card_id)
        # pequeño sleep para evitar lecturas duplicadas muy seguidas
        time.sleep(0.05)


def run_serial_loop(device: str, baud: int, mqtt_client: Optional[MQTTClient], mqtt_topic: Optional[str]):
    """
    Bucle principal leyendo desde un puerto serial.
    """
    global running
    if serial is None:
        log.error("pyserial no está instalado. Instálalo con `pip install pyserial` para usar modo serial.")
        return

    try:
        ser = serial.Serial(device, baudrate=baud, timeout=1)
    except Exception as e:
        log.exception("No se pudo abrir el puerto serial %s: %s", device, e)
        return

    log.info("Abierto puerto serial %s a %dbps. Esperando lecturas...", device, baud)
    try:
        while running:
            try:
                raw = ser.readline()  # lee hasta \n
            except Exception:
                log.exception("Error leyendo serial")
                break
            if not raw:
                continue
            try:
                card_id = raw.decode("utf-8", errors="ignore").strip()
            except Exception:
                card_id = raw.strip()
            if not card_id:
                continue
            log.info("Tarjeta serial detectada: %s", card_id)

            if mqtt_client and mqtt_topic:
                try:
                    mqtt_client.publish(mqtt_topic, card_id)
                except Exception:
                    log.exception("Error publicando a MQTT")

            ok = insert_supabase_record(card_id)
            if not ok:
                log.warning("Registro fallido para %s desde serial.", card_id)
            time.sleep(0.05)
    finally:
        try:
            ser.close()
        except Exception:
            pass


def main():
    parser = argparse.ArgumentParser(description="Registrar lecturas RFID en Supabase (input o serial).")
    parser.add_argument("--mode", choices=["input", "serial"], default="input", help="Modo de lectura")
    parser.add_argument("--serial-device", help="Puerto serial (ej. /dev/ttyUSB0 o COM3)")
    parser.add_argument("--baud", type=int, default=9600, help="Baudrate para serial")
    parser.add_argument("--mqtt", action="store_true", help="Publicar lecturas también en MQTT")
    parser.add_argument("--mqtt-broker", default=os.getenv("MQTT_BROKER", "localhost"), help="Broker MQTT")
    parser.add_argument("--mqtt-port", type=int, default=int(os.getenv("MQTT_PORT", 1883)), help="Puerto MQTT")
    parser.add_argument("--mqtt-topic", default=os.getenv("MQTT_TOPIC", "rfid/access"), help="Topic MQTT")
    args = parser.parse_args()

    mqtt_client = None
    if args.mqtt:
        try:
            mqtt_client = MQTTClient(args.mqtt_broker, args.mqtt_port)
            mqtt_client.connect()
        except Exception as e:
            log.exception("No se pudo iniciar cliente MQTT: %s", e)
            mqtt_client = None

    try:
        if args.mode == "input":
            run_input_loop(mqtt_client, args.mqtt_topic if args.mqtt else None)
        elif args.mode == "serial":
            device = args.serial_device or os.getenv("SERIAL_DEVICE")
            if not device:
                log.error("Modo serial requiere --serial-device o variable de entorno SERIAL_DEVICE")
                return
            run_serial_loop(device, args.baud, mqtt_client, args.mqtt_topic if args.mqtt else None)
    finally:
        if mqtt_client:
            mqtt_client.disconnect()
        log.info("Finalizado.")


if __name__ == "__main__":
    main()