#!/bin/bash

# Configuración
NGROK_PORT=1880
NGROK_URL_FILE="/home/recomputer/ngrok_url.txt"
NGROK_LOG_FILE="/home/recomputer/ngrok_monitor.log"
PA_ENDPOINT="https://default66e853deece344dd9d66ee6bdf4159.d4.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/629b53c1d07342ba8e1b86846663416f/triggers/manual/paths/invoke?api-version=1&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=5xJtyQk7F-WakiGVSRPrrTwzHAq3Wccc-krxkPN6BXY"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$NGROK_LOG_FILE"
}

get_ngrok_url() {
    curl --silent http://127.0.0.1:4040/api/tunnels | \
    grep -o '"public_url":"https[^"]*' | \
    sed 's/"public_url":"//'
}

send_to_power_automate() {
    local url=$1
    local retry=0
    local max_retries=5
    local success=0
    while [ $retry -lt $max_retries ]; do
        response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$PA_ENDPOINT" \
            -H "Content-Type: application/json" \
            -d "{\"ngrok_url\":\"$url\"}")
        if [ "$response" == "200" ] || [ "$response" == "202" ]; then
            log "URL enviada a Power Automate: $url"
            success=1
            break
        else
            log "Error enviando a Power Automate (HTTP $response). Reintentando en 5s..."
            sleep 5
            retry=$((retry+1))
        fi
    done
    if [ $success -eq 0 ]; then
        log "Falló el envío a Power Automate después de $max_retries intentos"
    fi
}

# Arrancar ngrok
log "Iniciando ngrok en el puerto $NGROK_PORT..."
/usr/local/bin/ngrok http $NGROK_PORT --log=stdout >/tmp/ngrok.log 2>&1 &
NGROK_PID=$!
log "Ngrok iniciado con PID $NGROK_PID"

# Esperar URL pública
URL=""
while [ -z "$URL" ]; do
    sleep 1
    URL=$(get_ngrok_url)
done

echo "$URL" > "$NGROK_URL_FILE"
log "URL pública detectada: $URL"
send_to_power_automate "$URL"

# Monitorear cambios de URL
PREV_URL="$URL"
while kill -0 $NGROK_PID >/dev/null 2>&1; do
    sleep 5
    URL=$(get_ngrok_url)
    if [ "$URL" != "$PREV_URL" ] && [ -n "$URL" ]; then
        echo "$URL" > "$NGROK_URL_FILE"
        log "URL cambiada: $URL. Actualizando Power Automate..."
        send_to_power_automate "$URL"
        PREV_URL="$URL"
    fi
done

log "Ngrok detenido. Script finalizado."