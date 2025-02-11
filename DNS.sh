#!/bin/bash
echo "*********_CONFIGURAR DNS EN UBUNTU SERVER_************"

ip=""
dominio=""

#USO DE FUNCIONES PARA VALIDAR TANTO LA IP COMO EL DOMINIO
validacion_ip_correcta()
{
    local ip="$1" #primer argumento para la funcion
    local regex_ipv4='^([0-9]{1,3}\.){3}[0-9]{1,3}$' #expresion para cuidar el formato de IPV4, 4 octetos, separados por ., de 1-3 digitos

    if [[ ! $ip =~ $regex_ipv4 ]]; then      #Comparacion de la ip ingresada con el formato
    echo "La IP ingresada no tiene el formato válido."    #Si es diferente, mensaje de error.
    return 1    #indicar fallo
    fi

    #Verificar cada octeto de la IP (valores entre 0 y 255)
    IFS='.' read -r -a octetos <<< "$ip"    #La IP se divide en un array llamado octetos usando el punto como separador.
    for octeto in "${octetos[@]}"; do       #Iteramos sobre cada octeto de la IP.
        if ! [[ "$octeto" =~ ^[0-9]+$ ]] || [ "$octeto" -lt 0 ] || [ "$octeto" -gt 255 ]; then
            echo "Error. La IP no es válida, los octetos deben estar entre 0 y 255."
            return 1
        fi
    done

    #Validar que no sean direcciones de red o broadcast
    IFS='.' read -r -a ip_array <<< "$ip"

    #Dirección de red si el último octeto es 0
    if [ "${ip_array[3]}" -eq 0 ]; then
        echo "Error. La IP $ip es una dirección de red y no es válida."
        return 1
    fi

    #Dirección de broadcast si el último octeto es 255
    if [ "${ip_array[3]}" -eq 255 ]; then
        echo "ERROR. La IP ingresada es una dirección de broadcast y no es válida."
        return 1
    fi

    echo "Okay, la IP ingresada es válida..."
    return 0

}

validacion_dominio()
{
    local dominio="$1" 

    #Convertir a minúsculas
    dominio=$(echo "$dominio" | tr '[:upper:]' '[:lower:]')

    #Expresión regular para validar el formato del dominio
    local regex='^(www\.)?[a-z0-9-]{1,30}\.[a-z]{2,6}$'

    #Verificamos si el dominio tiene el formato correcto, si no, mensaje de error
    if [[ ! $dominio =~ $regex ]]; then
        echo "El dominio $dominio no tiene el formato válido."
        return 1
    fi

    #Verificar que no empiece o termine con un guion segun las reglas de DNS
    if [[ "$dominio" =~ ^- || "$dominio" =~ -$ ]]; then
        echo "El dominio no puede empezar ni terminar con un guion."
        return 1
    fi

    echo "Okay, el dominio es válido..."
    return 0
}

#Pedir la IP hasta que sea válida
while true; do
    read -p "Ingrese la IP: " ip
    #Llamamos a la función de validación
    validacion_ip_correcta "$ip"
    #Si la IP es válida (return 0), salimos del bucle
    if [ $? -eq 0 ]; then
        break
    fi
done

#Pedir el DOMINIO hasta que sea valido
while true; do
    read -p "Ingrese el dominio: " dominio
    validacion_dominio "$dominio"
    if [ $? -eq 0 ]; then   #Si el dominio es válido sale del bucle
        break
    fi
done

# Configurar la IP estática
ARCHIVO_NETPLAN="/etc/netplan/50-cloud-init.yaml"
ADAPTADOR2="enp0s8"  # Adaptador de red 2 (RED INTERNA)
sudo bash -c "cat > $ARCHIVO_NETPLAN" <<EOL
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: true
    $ADAPTADOR2:
      dhcp4: no
      addresses:
        - $ip/24
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
EOL

echo "Configurando IP estática..."

sudo netplan apply  #Confirmar cambios y aplicarlos
echo "Aplicando cambios..."

#INSTALAR BIND9 con sus herramientas y archivos
sudo apt update    #actualizar paquetes
sudo apt-get install bind9 bind9utils bind9-doc
echo "Instalando BIND9..."

#CONFIGURACION DE BIND9
ARCHIVO_NCO="/etc/bind/named.conf.options"
sudo bash -c "cat > $ARCHIVO_NCO" <<EOL
options {
    directory "/var/cache/bind";

    forwarders {
        8.8.8.8;
    };

    dnssec-validation auto;

    listen-on-v6 { any; };
};
EOL
echo "Configurando BIND9..."

#CONFIGURACIÓN DE LA ZONA DIRECTA
ARCHIVO_ZONA="/etc/bind/db.$dominio"
sudo bash -c "cat > $ARCHIVO_ZONA" <<EOL
;
; Archivo de zona directa para el dominio
;
\$TTL 604800
@     IN  SOA     $dominio. root.$dominio. (
                         2     ; Serial
                    604800     ; Refresh
                     86400     ; Retry
                   2419200     ; Expire
                    604800 )   ; Negative Cache TTL
;
@     IN  NS      $dominio.
@     IN  A       $ip
www   IN  CNAME   $dominio.
EOL
echo "Configurando la zona directa..."

#CONFIGURACION LOCAL (named.conf.local)
ARCHIVO_CONF_LOCAL="/etc/bind/named.conf.local"
PRIMEROS_3_OCTETOS=$(echo $ip | cut -d'.' -f1-3 | awk -F. '{print $3"."$2"."$1}')
sudo bash -c "cat > $ARCHIVO_CONF_LOCAL" <<EOL
zone "$dominio" {
    type master;
    file "$ARCHIVO_ZONA";
};

zone "$PRIMEROS_3_OCTETOS.in-addr.arpa" {
    type master;
    file "/etc/bind/db.$PRIMEROS_3_OCTETOS";
};
EOL
echo "Configurando la zona local..."

ARCHIVO_3OCT_IP_INVERSA="/etc/bind/db.$PRIMEROS_3_OCTETOS"
ultoct=$(echo $ip | awk -F. '{print $4}')
sudo bash -c "cat > $ARCHIVO_3OCT_IP_INVERSA" <<EOL
;
;   BIND REVERSE DATA FILE FOR LOCAL LOOPBACK INTERFACE
;
\$TTL   604800
@       IN          SOA         $dominio. root.$dominio. (
                                     1    ; Serial
                                604800    ; Refresh
                                 86400    ; Retry
                               2419200    ; Expire
                                604800 )  ; Negative Cache TTL
;
@       IN          NS          $dominio.
$ultoct IN          PTR         $dominio.
EOL
echo "Configurando la zona inversa..."

#Agregar configuraciones a /etc/resolv.conf de manera segura
sudo sed -i "/^search /c\search $dominio" /etc/resolv.conf 
sudo sed -i "/^nameserver /c\nameserver $ip" /etc/resolv.conf 
echo "domain $dominio" | sudo tee -a /etc/resolv.conf > /dev/null
echo "options edns0 trust-ad" | sudo tee -a /etc/resolv.conf > /dev/null
echo "Actualizando archivo resolv.conf"

#REINICIAR BIND9 para aplicar cambios
sudo service bind9 restart
echo "REINICIANDO SERVICIO BIND9"
#COMPROBAR STATUS de bind9
sudo service bind9 status

echo "CONFIGURACIÓN COMPLETADA. :)"
