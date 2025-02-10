Write-Host "[[[[[[[[[[[[[[[[... CONFIGURACION DNS EN WINDOWS SERVER ...]]]]]]]]]]]]]]]]"

#Variables para la ip y el dominio
$IP = ""
$DOMINIO = ""

#FUNCIONES PARA VALIDAD TANTO LA IP COMO EL DOMINIO
#Función para validar IP
function validacion_ip_correcta {
    param ( [string]$IP )
    $regex_ipv4 = '^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if ($IP -notmatch $regex_ipv4) {
        Write-Host "La IP ingresada no tiene el formato válido."
        return $false
    }

    $octets = $IP.Split('.')
    foreach ($octet in $octets) {
        if ($octet -lt 0 -or $octet -gt 255) {
            Write-Host "Error: La IP no es válida, los octetos deben estar entre 0 y 255."
            return $false
        }
    }

    if ($octets[3] -eq 0) {
        Write-Host "Error: La IP ingresada es una dirección de red y no es válida."
        return $false
    }

    if ($octets[3] -eq 255) {
        Write-Host "Error: La IP ingresada es una dirección de broadcast y no es válida."
        return $false
    }

    Write-Host "Okay, la IP ingresada es válida..."
    return $true
}

#Función para validar dominio
function validacion_dominio {
    param ( [string]$DOMINIO )

    $regex_dominio = '^(www\.)?[a-z0-9-]{1,30}\.[a-z]{2,6}$'

    if ($DOMINIO -notmatch $regex_dominio) {
        Write-Host "El dominio $DOMINIO no tiene el formato válido."
        return $false
    }

    if ($DOMINIO.StartsWith("-") -or $DOMINIO.EndsWith("-")) {
        Write-Host "El dominio no puede empezar ni terminar con un guion."
        return $false
    }

    Write-Host "Okay, el dominio es válido..."
    return $true
}

#Pedir la IP hasta que sea válida
while ($true) {
    $IP = Read-Host "Ingrese la IP: "
    if (validacion_ip_correcta $IP) {
        break
    }
}

#Pedir el dominio hasta que sea válido
while ($true) {
    $DOMINIO = Read-Host "Ingrese el dominio: "
    if (validacion_dominio $DOMINIO) {
        break
    }
}

#DIVIDIR LA IP EN OCTETOS Y ALACENARLOS EN UN ARRAY, SEPARANDO POR EL PUNTO
$OCTETOS = $IP -split '\.'
#Los tres primeros octetos
$Ptres_OCT = "$($OCTETOS[0]).$($OCTETOS[1]).$($OCTETOS[2])"  
#Los tres primeros octetos invertidos
$Ptres_INV_OCT = "$($OCTETOS[2]).$($OCTETOS[1]).$($OCTETOS[0])"
#Ultimo octeto
$ULT_OCT = $OCTETOS[3]

#Configuración del servidor DNS
Write-Host "Configurando el servidor DNS con la IP: $IP y el DOMINIO: $DOMINIO..."

#PONER LA IP ESTÁTICA en la interfaz de red (RED INTERNA)
New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress $IP -PrefixLength 24
Write-Host "La IP se configuró estática...."
#Configurar la dirección del servidor DNS en la interfaz de red "Ethernet 2"
Set-DnsClientServerAddress -InterfaceAlias "Ethernet 2" -ServerAddresses "$IP", "8.8.8.8"
Write-Host "Configurando la dirección del servidor DNS con la interfaz de red..."

#INSTALAR EL SERVICIO DE DNS y sus herramientas de administración
Write-Host "COMENZANDO INSTALACIÓN DEL SERVICIO DNS"
Install-WindowsFeature -Name DNS -IncludeManagementTools
Get-WindowsFeature -Name DNS        #VERIFICACIÓN DE INSTALACIÓN

#CREAR Y CONFIGURAR LAS ZONAS DNS
Add-DnsServerPrimaryZone -Name "$DOMINIO" -ZoneFile "$DOMINIO.dns" -DynamicUpdate None
Add-DnsServerResourceRecordA -Name "@" -ZoneName "$DOMINIO" -IPv4Address "$IP"          #Crear un registro A para el dominio principal
Add-DnsServerResourceRecordCNAME -Name "www" -ZoneName "$DOMINIO" -HostNameAlias "$DOMINIO"     #Crear un registro CNAME para "www"
Add-DnsServerPrimaryZone -Network "$Ptres_OCT.0/24" -ZoneFile "$Ptres_OCT.dns" -DynamicUpdate None      #Configurar zona inversa para la IP
Add-DnsServerResourceRecordPtr -Name "$ULT_OCT" -ZoneName "$Ptres_INV_OCT.in-addr.arpa" -PtrDomainName "$DOMINIO"       #Crear un registro PTR para la resolución inversa
Get-DnsServerZone

#REINICIANDO EL SERVICIO PARA APLICAR CAMBIOS
Restart-Service -Name DNS
Write-Host "EL SERVICIO SE ESTA REINICIANDO...."

#CONFIGURAR LA REGLA PARA PODER HACER PING CON EL CLIENTE
Write-Host "Configurando para poder recibir y hacer ping con el cliente..."
New-NetFirewallRule -DisplayName "Permitir Ping Entrante" -Direccion Inbound -Protocol ICMPv4 -Action Allow

Write-Host "*** LISTO CONFIGURACIÓN COMPLETADA :) ***"
