#!/usr/bin/env wish
# Bosch BLE - Diagnostico Tcl/Tk para AndroWish y PC
# No establece por si solo una conexion GATT: requiere un puente BLE -> TCP.
package require Tk
namespace eval ::BLE {
    variable server ""
    variable clients {}
    variable port 8765
    variable packetCount 0
    variable status "Sin iniciar"
    variable portText "8765"
    variable hexText ""
    variable version "2.1"
    variable lastHex ""
    variable lastBytes ""
}
wm title . "Bosch BLE - Diagnostico doble modo v2.1"
wm geometry . 850x650
catch {wm minsize . 580 450}
option add *Font {TkDefaultFont 11}

proc ::BLE::log {message} {
    .main.log configure -state normal
    .main.log insert end "[clock format [clock seconds] -format {%H:%M:%S}]  $message\n"
    .main.log see end
    .main.log configure -state disabled
}
proc ::BLE::asHex {bytes} {
    binary scan $bytes H* h
    return [string toupper [join [regexp -all -inline {..} $h] " "]]
}
proc ::BLE::recordPacket {source bytes} {
    variable packetCount
    incr packetCount
    set n [string length $bytes]
    variable lastHex
    variable lastBytes
    set lastBytes $bytes
    set lastHex [asHex $bytes]
    log "PAQUETE #$packetCount | $source | $n bytes | $lastHex"
    set ::BLE::status "Recibidos: $packetCount paquetes (ultimo: $n bytes)"
}
proc ::BLE::parseHex {} {
    variable hexText
    set s [string map {" " "" ":" "" "-" "" "\t" ""} [string trim $hexText]]
    if {$s eq "" || [string length $s] % 2 || ![regexp -nocase {^[0-9a-f]+$} $s]} {
        tk_messageBox -icon warning -message "Introduce bytes hexadecimales completos, por ejemplo: 01 02 A0 FF"
        return
    }
    if {[catch {set bytes [binary format H* $s]} err]} {
        log "Error convirtiendo hexadecimal: $err"
        return
    }
    recordPacket "Entrada manual" $bytes
}
proc ::BLE::accept {sock addr remotePort} {
    variable clients
    lappend clients $sock
    fconfigure $sock -blocking 0 -buffering line -translation lf -encoding utf-8
    fileevent $sock readable [list ::BLE::readClient $sock]
    log "Puente conectado desde $addr:$remotePort"
}
proc ::BLE::readClient {sock} {
    variable clients
    set err ""
    if {[catch {set count [gets $sock line]} err]} {
        log "Error en puente: $err"
        set count -1
    }
    if {$count < 0} {
        if {[eof $sock] || $err ne ""} {
            catch {close $sock}
            set pos [lsearch -exact $clients $sock]
            if {$pos >= 0} {set clients [lreplace $clients $pos $pos]}
            log "Puente desconectado"
        }
        return
    }
    set line [string trim $line]
    if {$line eq ""} {return}
    # Formato del puente: una linea por notificacion, bytes en HEX.
    # Prefijo opcional HEX: o DATA:
    regsub -nocase {^(HEX|DATA):\s*} $line {} line
    set compact [string map {" " "" ":" "" "-" "" "\t" ""} $line]
    if {[regexp -nocase {^[0-9a-f]+$} $compact] && [string length $compact] % 2 == 0} {
        if {![catch {set bytes [binary format H* $compact]}]} {
            recordPacket "Puente TCP" $bytes
            return
        }
    }
    log "MENSAJE del puente: $line"
}
proc ::BLE::start {} {
    variable server
    variable portText
    variable port
    variable status
    if {$server ne ""} {log "Servidor ya iniciado"; return}
    if {![string is integer -strict $portText] || $portText < 1024 || $portText > 65535} {
        tk_messageBox -icon warning -message "Puerto no valido (1024-65535)"
        return
    }
    set port $portText
    if {[catch {set server [socket -server ::BLE::accept -myaddr 127.0.0.1 $port]} err]} {
        set status "Error al iniciar"
        log "No se pudo iniciar TCP: $err"
        return
    }
    set status "Escuchando en 127.0.0.1:$port"
    log "Servidor local listo. Esperando puente BLE -> TCP."
}
proc ::BLE::stop {} {
    variable server
    variable clients
    variable status
    foreach sock $clients {catch {close $sock}}
    set clients {}
    if {$server ne ""} {catch {close $server}; set server ""}
    set status "Detenido"
    log "Servidor detenido"
}
proc ::BLE::capabilities {} {
    log "--- INFORMACION DEL ENTORNO ---"
    log "Tcl: [info patchlevel] | Tk: [package provide Tk] | OS: $::tcl_platform(os)"
    log "Comando borg: [expr {[llength [info commands borg]] ? {DISPONIBLE} : {NO DISPONIBLE}}]"
    if {[llength [info commands borg]]} {
        # No llamar a subcomandos inventados como "le": varias versiones de
        # AndroWish devuelven "unknown argument le".
        if {[catch {borg bluetooth} result]} {
            log "Ayuda/resultado de borg bluetooth: $result"
        } else {
            log "Resultado de borg bluetooth: $result"
        }
        log "No se ejecutan comandos de escaneo no verificados."

    }
    log "Nota: estos sondeos no demuestran soporte GATT ni conexion BLE."
}
proc ::BLE::save {} {
    set path [tk_getSaveFile -title "Guardar registro" -defaultextension .txt -filetypes {{"Texto" {.txt}} {"Todos" {*}}}]
    if {$path eq ""} {return}
    if {[catch {set f [open $path w]; puts $f [.main.log get 1.0 end]; close $f} err]} {
        tk_messageBox -icon error -message "Error al guardar: $err"
    } else {log "Registro guardado: $path"}
}
proc ::BLE::close {} {stop; destroy .}

frame .main -padx 10 -pady 10
pack .main -fill both -expand 1
label .main.title -text "Bosch GLM 50-27 C | Monitor de paquetes" -font {TkDefaultFont 14 bold}
pack .main.title -anchor w -pady {0 6}
label .main.note -text "Modo A: detectar capacidades BLE nativas de AndroWish. Modo B: recibir notificaciones reales del puente Android BLE (proyecto incluido)." -wraplength 750 -justify left
pack .main.note -anchor w -pady {0 8}
frame .main.top
pack .main.top -fill x
label .main.top.portLabel -text "Puerto TCP:"
entry .main.top.port -textvariable ::BLE::portText -width 7
button .main.top.start -text "Iniciar receptor" -command ::BLE::start
button .main.top.stop -text "Detener" -command ::BLE::stop
button .main.top.cap -text "Probar modo nativo" -command ::BLE::capabilities
pack .main.top.portLabel .main.top.port .main.top.start .main.top.stop .main.top.cap -side left -padx 3 -pady 3
label .main.status -textvariable ::BLE::status -anchor w
pack .main.status -fill x -pady 4
frame .main.hex
pack .main.hex -fill x -pady 5
label .main.hex.label -text "Paquete HEX:"
entry .main.hex.entry -textvariable ::BLE::hexText
button .main.hex.send -text "Procesar" -command ::BLE::parseHex
pack .main.hex.label -side left -padx 3
pack .main.hex.send -side right -padx 3
pack .main.hex.entry -side left -fill x -expand 1 -padx 3
frame .main.logFrame
pack .main.logFrame -fill both -expand 1 -pady 5
scrollbar .main.scroll -command {.main.log yview}
text .main.log -yscrollcommand {.main.scroll set} -wrap word -state disabled -font {Courier 10}
pack .main.scroll -in .main.logFrame -side right -fill y
pack .main.log -in .main.logFrame -side left -fill both -expand 1
frame .main.bottom
pack .main.bottom -fill x
button .main.bottom.save -text "Guardar registro" -command ::BLE::save
button .main.bottom.clear -text "Limpiar" -command {.main.log configure -state normal; .main.log delete 1.0 end; .main.log configure -state disabled}
button .main.bottom.exit -text "Salir" -command ::BLE::close
pack .main.bottom.save .main.bottom.clear -side left -padx 4
pack .main.bottom.exit -side right -padx 4
wm protocol . WM_DELETE_WINDOW ::BLE::close
::BLE::log "Monitor listo. Pulsa 'Probar modo nativo' para inspeccionar AndroWish."
::BLE::log "Modo puente: iniciar receptor y abrir app Android Bosch BLE Bridge. El receptor escucha en 127.0.0.1:8765."
::BLE::log "Modo nativo: diagnostica disponibilidad borg. Sin API GATT documentada no puede abrir BLE automaticamente."
