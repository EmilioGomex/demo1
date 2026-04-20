#!/usr/bin/env python3
import os
import sys
import time
import json
import argparse
import logging
import signal
import threading
import queue
from datetime import datetime, timezone
from typing import Optional

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from dotenv import load_dotenv

# Intentar imports opcionales
try:
    import serial
except ImportError:
    serial = None

try:
    import paho.mqtt.client as mqtt
except ImportError:
    mqtt = None

# Carga de configuración
load_dotenv()
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")
MAQUINA_ID = os.getenv("MAQUINA_ID", "9991")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("ERROR: Falta SUPABASE_URL o SUPABASE_KEY en el entorno.")
    sys.exit(1)

# Logging profesional
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
log = logging.getLogger("rfid_sync")

# Sesión HTTP con reintentos automáticos
session = requests.Session()
retry_strategy = Retry(
    total=3,
    status_forcelist=[429, 500, 502, 503, 504],
    backoff_factor=1,
)
session.mount("https://", HTTPAdapter(max_retries=retry_strategy))

headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=minimal"
}

# Cola para lecturas pendientes (buffer local)
pending_queue = queue.Queue()
running = True

def handle_sigint(signum, frame):
    global running
    log.info("Cerrando script de forma limpia...")
    running = False

signal.signal(signal.SIGINT, handle_sigint)
signal.signal(signal.SIGTERM, handle_sigint)

# =======================
# LÓGICA DE ENVÍO (WORKER)
# =======================
def supabase_worker():
    """Hilo encargado de vaciar la cola de lecturas hacia Supabase."""
    while running or not pending_queue.empty():
        try:
            card_id = pending_queue.get(timeout=1)
        except queue.Empty:
            continue

        success = False
        while not success and running:
            try:
                payload = {
                    "id_operador": str(card_id),
                    "procesado": False,
                    "fecha_lectura": datetime.now(timezone.utc).isoformat()
                }
                resp = session.post(SUPABASE_URL, headers=headers, json=payload, timeout=10)
                
                if resp.status_code in (200, 201, 204):
                    log.info(f"ÉXITO: Tarjeta {card_id} enviada a Supabase.")
                    success = True
                else:
                    log.error(f"ERROR Supabase ({resp.status_code}): {resp.text}. Reintentando en 5s...")
                    time.sleep(5)
            except Exception as e:
                log.error(f"Fallo de conexión: {e}. Reintentando en 5s...")
                time.sleep(5)
        
        pending_queue.task_done()

# =======================
# BUCLE DE LECTURA
# =======================
def run_loop(mode, device=None, baud=9600, mqtt_client=None, topic=None):
    last_card = None
    last_time = 0
    
    ser = None
    if mode == "serial":
        if not serial:
            log.error("pyserial no instalado.")
            return
        ser = serial.Serial(device, baud, timeout=0.1)
        log.info(f"Escuchando Serial en {device}...")
    else:
        log.info("Escuchando Teclado (Input)...")

    while running:
        try:
            if mode == "serial":
                line = ser.readline().decode('utf-8', errors='ignore').strip()
            else:
                line = input().strip()
            
            if not line: continue
            
            # Debounce: Evitar lecturas duplicadas en menos de 2 segundos
            current_time = time.time()
            if line == last_card and (current_time - last_time) < 2:
                continue
                
            log.info(f"TARJETA DETECTADA: {line}")
            last_card = line
            last_time = current_time

            # 1. Enviar a MQTT (opcional, inmediato)
            if mqtt_client and topic:
                try:
                    mqtt_client.publish(topic, line)
                except Exception as e:
                    log.error(f"Error MQTT: {e}")

            # 2. Poner en cola para Supabase
            pending_queue.put(line)

        except EOFError: break
        except Exception as e:
            log.error(f"Error en lectura: {e}")
            time.sleep(1)

    if ser: ser.close()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["input", "serial"], default="input")
    parser.add_argument("--serial-device", default="/dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=9600)
    parser.add_argument("--mqtt", action="store_true")
    args = parser.parse_args()

    # Iniciar Hilo de Envío
    worker_thread = threading.Thread(target=supabase_worker, daemon=True)
    worker_thread.start()

    mqtt_c = None
    topic = f"maquina/{MAQUINA_ID}/rfid"
    if args.mqtt and mqtt:
        mqtt_c = mqtt.Client(client_id=f"rpi_rfid_{MAQUINA_ID}")
        try:
            mqtt_c.connect("localhost", 1883, 60)
            mqtt_c.loop_start()
        except Exception as e:
            log.error(f"MQTT no disponible: {e}")

    try:
        run_loop(args.mode, args.serial_device, args.baud, mqtt_c, topic)
    finally:
        log.info("Esperando a que se vacíe la cola de envíos...")
        pending_queue.join()
        if mqtt_c: mqtt_c.disconnect()

if __name__ == "__main__":
    main()