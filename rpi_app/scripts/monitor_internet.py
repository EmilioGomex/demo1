import os
import time
import subprocess

HOST = "8.8.8.8"
INTERVALO = 10
MAX_FALLOS = 6

fallos = 0

while True:
    respuesta = subprocess.call(
        ["ping", "-c", "1", "-W", "2", HOST],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

    if respuesta == 0:
        fallos = 0
    else:
        fallos += 1

    if fallos >= MAX_FALLOS:
        os.system("reboot")
        break

    time.sleep(INTERVALO)